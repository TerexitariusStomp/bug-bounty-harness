# bb-lab — full deployment guide

The exact install we ran on Arch/Omarchy (24 cores, 30 GB RAM, RTX GPU).
Expect ~1-3 hours: heavy Docker pulls (reNgine ~5 GB, Shannon ~3.5 GB,
Strix sandbox ~5.9 GB, eth-toolbox ~3 GB) and source builds.

## Phase 0 — prerequisites

- Arch/Debian-ish Linux, Docker + compose plugin, Go, Python 3.11+,
  Node/npm, cargo (pacman `rust`), uv, git, pnpm.
- `systemctl --user` works and `loginctl enable-linger $USER` (timers
  survive logout — required for the automation to actually be automated).

## Phase 1 — secrets & env

```bash
cp .env.example .env
```

Fill in:

| Var | Where to get it | Required for |
|---|---|---|
| `LITELLM_MASTER_KEY` | `sk-` + `openssl rand -hex 24` | router start (empty = UnsafeMasterKeyError) |
| `TELEGRAM_BOT_TOKEN` | @BotFather → /newbot | alerts |
| `TELEGRAM_CHAT_ID` | @userinfobot | alerts |
| `OPENROUTER_API_KEY` | openrouter.ai (free models work — rate-limited but free) | tier-a without paid keys |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY` | providers | frontier tier-a (best agents) |
| `DOJO_URL`, `DOJO_API_TOKEN` | generated in Phase 3 | findings DB |

**Gotcha:** docker compose interpolates from `.env` in the *compose
directory* (or `env_file`), not the repo root — we symlink
`ln -s ../.env compose/.env`.

## Phase 2 — host toolchain

```bash
./bootstrap.sh
```

What it actually installs and the fixes we needed upstream:

| Tool | How | Gotcha hit |
|---|---|---|
| PD suite (nuclei, httpx, katana, subfinder, naabu, dnsx, alterx, asnmap, cloudlist, notify, interactsh, mapcidr, proxify, uncover, tlsx, vulnx…) | `pdtm -ia` into `~/go/bin` | needs `export PATH=$HOME/go/bin` everywhere (done in `glue/bb-lib.sh`) |
| Strix | `pipx install strix-agent` | env vars: `STRIX_LLM`, `LLM_API_KEY`, `LLM_API_BASE`, `OPENAI_BASE_URL`, `STRIX_API_TYPE=chat_completions` |
| gau | `go install github.com/lc/gau@latest` | repo moved from tomnomnom → lc |
| jsluice, anew, git-dumper, ffuf, osv-scanner, kiterunner (`kr`) | go install | — |
| dalfox | `go install github.com/hahwul/dalfox/v2@latest` | — |
| arjun | `pipx install arjun` | AGPL — standalone CLI only |
| semgrep, gitleaks | pipx / distro package | — |
| trufflehog | **build from source** | `go install` fails on `replace` directives; GitHub releases 504'd → `git clone` + `go build ./cmd/trufflehog` |
| cloud_enum | clone + `uv sync` + run `uv run cloud_enum.py` | do NOT symlink a wrapper over `cloud_enum.py` — it clobbers the script |
| feroxbuster, cargo-audit | `cargo install` | needs `rust` (pacman); compiles a few min |
| zaproxy, mitmproxy, trivy, pandoc | pacman | `feroxbuster`/`ffuf` are NOT in pacman (use cargo/go) |
| LinkFinder, SecretFinder, SecLists, PayloadsAllTheThings | clone into `bounty/tools|wordlists` | — |
| nuclei-templates | `git clone --depth 1` into `run/nuclei-templates` | template-watch diffs against it |
| xbow-validation-benchmarks | clone into `run/` | `make run BENCHMARK=XBEN-XXX-24` is the deploy convention |

## Phase 3 — docker services

```bash
cd compose && docker compose up -d          # litellm first, validate /health
```

- **LiteLLM** must have a real `LITELLM_MASTER_KEY` or it refuses to boot.
- **Model reality check:** agent prompts (Strix especially) burst past 32k
  tokens. A small local model alone can't carry an agent run — keep
  `context_window_fallbacks: tier-b → tier-a` in `litellm.config.yaml`.
  Free OpenRouter models work but are rate-limited; paid keys = real speed.
- **DefectDojo**: clone `django-DefectDojo` under `run/`, use the
  `postgresql-redis` profile. Port 8080 was taken on our box → remap
  `8000:8080` to `8085:8080`. Grab the auto-generated admin password from
  `docker compose logs initializer`, trade it for an API token, enable
  deduplication (`Deduplication` + `Delete duplicates` in System Settings).
- **Juice Shop** lab: `docker run -d --name lab-juice -p 3000:3000 bkimminich/juice-shop`.
- **reNgine**: clone `rengine` into `run/`, `install.sh -n`. Two hits:
  GitHub release URLs 504-retry internally (just slow), and its bundled
  `ollama` container collides with a host Ollama on 11434 → edit
  `docker-compose.yml` port to `127.0.0.1:11435:11434`.
- **Shannon**: `docker pull keygraph/shannon:latest`; config at
  `~/.shannon/config.toml` + `--models-config run/shannon/models.json`
  for the LiteLLM route. It wants `-u url -r repo` (white-box; falls back
  to black-box lane without source).
- **eth-security-toolbox**: the tag is
  `ghcr.io/trailofbits/eth-security-toolbox/ci:nightly` (`:latest` doesn't exist).
- **damn-vulnerable-defi**: `tinchoabbate/` fork — the crytic URL is stale.

## Phase 4 — container→host networking (the part nobody documents)

Host UFW/firewall will silently drop container→host traffic. Agents in
containers can't reach `127.0.0.1` services by design — fix it on the host:

```bash
# bind host services beyond loopback, allow only docker subnets
llama-server --host 0.0.0.0 --port 8390 ...
sudo ufw allow from 172.16.0.0/12 to any port 8390,4000
# publish litellm on 0.0.0.0 (compose port "4000:4000" not "127.0.0.1:4000:4000")
# then agents target the bridge gateway IP (docker0 = 172.17.0.1, custom nets = their .1)
```

`host.docker.internal` resolves to 172.17.0.1 inside containers — cross-
bridge routing gets dropped; use each network's own gateway.

## Phase 5 — scope (the legal boundary, do not skip)

Edit `scope/targets.yaml` — only programs written here can be scanned:

```yaml
programs:
  - name: example-program
    platform: hackerone
    domains: ["*.example.com"]
    out_of_scope_regex: ["status\\.example\\.com"]
    rate_limit_rps: 100
    allows_automation: true
```

Verify the gate (it once shipped inverted — would have scanned OOS hosts;
now fixed and tested both directions):

```bash
source glue/bb-lib.sh
is_oos example-program status.example.com && echo OOS   # must say OOS
is_oos example-program api.example.com    || echo IN    # must say IN
```

## Phase 6 — timers + first runs

```bash
bash systemd/install-units.sh          # ~15 services+timers
systemctl --user list-timers 'bb-*'    # all armed
loginctl enable-linger $USER
printf 'example-program/api.example.com\t9\n' >> run/ev-queue.txt   # program/host<TAB>score
```

## Phase 7 — validation (do this before real targets)

```bash
# smoke: quick bench must pass
bash glue/bench-run.sh --quick
# E2E: nuclei → dojo-inbox → bb-sync → Dojo (dedup proven on re-import)
nuclei -u http://127.0.0.1:3000 -silent -jle -o run/dojo-inbox/lab.jsonl
bash glue/dojo-sync.sh
```

Bugs we found validating our own pipeline (all fixed — keep an eye out):
missing `run/evidence/` dir silently killed agent runs; stale queue
entries ran needless dispatches; `--target` needed URL scheme;
`docker compose restart` doesn't reload env (`up -d` does); LiteLLM
doesn't hot-reload `model_list` (restart it after config edits);
free-model slugs rot fast — verify against `openrouter.ai/api/v1/models`.

## Ongoing

- Timers handle: template-watch (15m), miners+intel (daily), web3 scan
  (nightly), canary updates + bench + yield (weekly), agent feed (2×/day).
- `~/bounty/` (sibling dir if you use it): `bounty-sync.timer` refreshes
  the program index daily at 06:30.
- Telegram pings on new findings once tokens are set.
- Re-run `./bootstrap.sh` anytime — it's idempotent.
