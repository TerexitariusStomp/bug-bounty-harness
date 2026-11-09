# bb-lab — self-evolving bug bounty harness

Local, fully-automated, OSS-only. Recon + secrets + JS mining, AI agents
(Strix/Shannon) on a tiered LiteLLM router (local uncensored + API models),
DefectDojo dedup memory, Telegram alerts, self-updating intel + canary tool
updates + yield analytics, EV-ranked targeting, exploit-chain synthesis,
self-benchmarking. ~95% off-the-shelf OSS; glue is bash/python/YAML.

> **Authorized targets only.** Every active scan passes a scope gate
> (`scope/targets.yaml`) — the harness refuses anything not written down
> as in-scope. Labs (Juice Shop, crAPI, Damn Vulnerable DeFi) are included
> for pipeline validation.

## Quick start

```bash
git clone <this repo> ~/bb-lab && cd ~/bb-lab
cp .env.example .env        # fill: LITELLM_MASTER_KEY, TELEGRAM_*, DOJO_URL, API keys
./bootstrap.sh              # phased install: host tools → docker stack → agents → labs
bash systemd/install-units.sh   # arm the timers (template-watch, miners, intel, bench…)
```

Then edit `scope/targets.yaml` + `scope/contracts.yaml`, drop targets into
`run/ev-queue.txt` (`program/host<TAB>score`), and the machine does the rest.

**Full walkthrough:** [`SETUP.md`](SETUP.md) — the complete deploy with every
upstream gotcha we hit (stale repos, moved orgs, UFW container networking,
model context limits, port collisions).

Bounty-beginner workflow lives in `bounty/` — `sync.py` ranks ~950 programs
from bounty-targets-data + diodb into a priority queue, `run_recon.sh` runs
the recon chain, `*_solve*.py` are lab-exercise runners (PortSwigger/Juice
Shop) that harvest techniques into `intel/playbooks/`.

Architecture:

```
senses ──► hunter ──► memory        cortex (evolution)      dominance
reNgine    Strix      DefectDojo     intel/ git repo          bb-bench
miners     Shannon    dedup+evid.    ingest·forge·update      bb-queue
edge       pwnkit     reports        analytics·model-bench    chains
                     ▲                      ▲                     ▲
                     └──────── LiteLLM router (tiered LLMs) ──────┘
```

## Live endpoints (this install)

| Service | URL | Notes |
|---|---|---|
| LiteLLM router | http://127.0.0.1:4000 | master key in .env |
| DefectDojo | http://127.0.0.1:8085 | admin / see run/dojo-admin.txt |
| llama-server (Ornith Tier-B) | 0.0.0.0:8390 | GPU, UFW-opened to docker subnets only |
| reNgine | https://127.0.0.1 (443) | after install.sh -n completes |
| Juice Shop lab | http://127.0.0.1:3000 | lab-local program target |
| Shannon dashboard | http://localhost:8233 | when a scan runs |

Port 8080 was taken on the build host — Dojo remapped to 8085 (adjust in
.env for your machine). The ensemble lane is a second Strix pass on the
opposite model tier — model diversity is the validation signal.

## Components

| Layer | Tool | License | Where it lives |
|---|---|---|---|
| Web orchestrator | reNgine 2.2+ | GPL-3.0 | `run/rengine/` (cloned by bootstrap) |
| Findings DB | DefectDojo | BSD-3 | `run/django-DefectDojo/` |
| Agent: white-box | Shannon | verify repo license | `run/shannon/` |
| Agent: black-box | Strix | Apache-2.0 | pipx/docker |
| Agent: ensemble | pwnkit | OSS | `run/pwnkit/` |
| LLM router | LiteLLM | MIT | `compose/` |
| Local LLM | llama.cpp server | MIT | `run/llama.cpp/` (existing ~/llama.cpp reused if present) |
| Contract suite | eth-security-toolbox + aderyn + trident | AGPL/GPL | docker + cargo |
| Edge daemon | certstream + git-watch | — | `glue/edge-watch.py` |

## Quick start

```bash
cd ~/bb-lab
cp .env.example .env && $EDITOR .env        # fill keys — at minimum TELEGRAM_*, DOJO_*, one Tier-A key
./bootstrap.sh --deps                        # system tools (go/pipx/cargo + scanners)
./bootstrap.sh --models                      # llama.cpp + Tier-B quants (dolphin3/abliterated)
./bootstrap.sh --stack                       # litellm compose up
./bootstrap.sh --dojo                        # clone+up DefectDojo, print where to grab API token
./bootstrap.sh --rengine                     # clone+install reNgine (interactive: admin creds)
./bootstrap.sh --agents                      # strix (pipx), shannon + pwnkit clones
./bootstrap.sh --units                       # systemd user timers
./bootstrap.sh --lab                         # pull lab fixtures (juice-shop, vuln contracts, benches)
./bootstrap.sh --verify                      # smoke checks
```

`scope/` holds what you're allowed to touch — edit `targets.yaml` first.
`intel/` is the evolving brain (git): generated templates, playbooks, wordlists,
quarantine lists, tool-eval decisions, bench history.

## Timers (systemd --user)

`bb-templatewatch` 15m · `bb-edge` continuous daemon · `bb-miners` daily ·
`bb-source` daily · `bb-web3` nightly · `bb-fuzz` weekly · `bb-sync` hourly ·
`bb-intel` 4h · `bb-update` daily canary · `bb-analytics` weekly ·
`bb-bench` weekly · `bb-queue` daily

## Rules that keep you alive

- Only assets in `scope/targets.yaml` + within each program's OOS regex ever get scanned.
- `BB_RATE_LIMIT` is the global ceiling; per-program overrides in targets.yaml.
- No finding is submitted without a validated PoC + human review.
- Disclose automation/AI where program policy requires it.
- `.env` and `intel/` stay local — `intel/` can contain target names.
