#!/usr/bin/env bash
# bootstrap.sh — phased installer for bb-lab. Run phases in order:
#   --deps --models --stack --dojo --rengine --agents --units --lab --verify
# Idempotent: safe to re-run any phase.
set -euo pipefail
BB="${BB_ROOT:-$HOME/bb-lab}"; . "$BB/glue/bb-lib.sh" 2>/dev/null || true
say(){ printf '\033[1m==>\033[0m %s\n' "$*"; }
ok(){ [[ -e $1 ]] && { say "skip (exists): $1"; return 0; } || return 1; }

deps(){
  say "system deps"
  command -v pacman >/dev/null && \
    sudo pacman -S --needed --noconfirm \
      docker docker-compose git go python python-pipx python-yaml \
      jq curl nmap openbsd-netcat 2>/dev/null || true
  pipx ensurepath >/dev/null 2>&1 || true
  say "python venv for edge daemon"
  python3 -m venv "$BB/run/venv"
  "$BB/run/venv/bin/pip" -q install websockets pyyaml
  say "PD toolchain via pdtm + go installs"
  go install github.com/projectdiscovery/pdtm/cmd/pdtm@latest
  "$HOME/go/bin/pdtm" -install-all -silent || true
  for t in trufflesecurity/trufflehog/v3 BishopFox/jsluice; do :; done
  go install github.com/trufflesecurity/trufflehog/v3@latest
  go install github.com/BishopFox/jsluice/cmd/jsluice@latest
  go install github.com/lc/gau/v2/cmd/gau@latest
  go install github.com/tomnomnom/anew@latest
  pipx install git-dumper || true; pipx install aderyn-driver || true
  cargo install cargo-audit 2>/dev/null || true
  pipx install slither-analyzer || true
  say "DONE deps"
}

models(){
  say "llama.cpp + tier-B quants"
  if [[ ! -d "$HOME/llama.cpp" ]]; then
    git clone --depth 1 https://github.com/ggml-org/llama.cpp "$HOME/llama.cpp"
  fi
  cmake -B "$HOME/llama.cpp/build" -S "$HOME/llama.cpp" -DGGML_NATIVE=ON \
    >/dev/null && cmake --build "$HOME/llama.cpp/build" -j --target llama-server
  mkdir -p "$HOME/models"
  say "download Tier-B quants (~5-8GB each) — pick current best via model-bench later"
  echo "  candidates (huggingface, GGUF):"
  echo "   cognitivecomputations/Dolphin3.0-Llama3.1-8B-GGUF (Q6_K)"
  echo "   huihui-ai abliterated Qwen/Llama quants (search 'abliterated GGUF')"
  echo "   WhiteRabbitNeo/WhiteRabbitNeo-V3-7B-GGUF (legacy baseline)"
  echo "  → place .gguf files in ~/models/ and set BB_TIERB_MODEL in .env"
}

stack(){
  say "litellm router up"
  (cd "$BB/compose" && docker compose up -d)
  sleep 5; curl -fsS http://127.0.0.1:4000/health/liveliness && echo
}

dojo(){
  say "DefectDojo"
  if [[ ! -d "$BB/run/django-DefectDojo" ]]; then
    git clone --depth 1 https://github.com/DefectDojo/django-DefectDojo \
      "$BB/run/django-DefectDojo"
  fi
  (cd "$BB/run/django-DefectDojo" && ./dc-up.sh postgres-redis 2>/dev/null \
    || docker compose up -d)
  say "Dojo will be at http://127.0.0.1:8080 — create admin, then set DOJO_API_TOKEN in .env"
}

rengine(){
  say "reNgine"
  if [[ ! -d "$BB/run/rengine" ]]; then
    git clone --depth 1 https://github.com/yogeshojha/rengine "$BB/run/rengine"
  fi
  say "run its installer (interactive — sets admin creds + TLS):"
  echo "  cd $BB/run/rengine && sudo ./install.sh"
  say "after install: Settings → notifications → Telegram; upload nuclei templates"
}

agents(){
  say "agent lanes"
  pipx install strix-agent 2>/dev/null || pipx upgrade strix-agent 2>/dev/null || \
    echo "strix: pipx install strix-agent"
  ok "$BB/run/shannon" || \
    git clone --depth 1 https://github.com/KeygraphHQ/shannon "$BB/run/shannon"
  ok "$BB/run/pwnkit" || \
    git clone --depth 1 https://github.com/pwnkit/pwnkit "$BB/run/pwnkit" || \
    echo "pwnkit: check repo url (docs.pwnkit.com)"
  say "point Strix at litellm: OPENAI_BASE_URL=$LITELLM_BASE/v1 (strix-feed already does)"
  say "Shannon: check $BB/run/shannon/README for env/config"
}

units(){ bash "$BB/systemd/install-units.sh"; }

lab(){
  say "lab fixtures"
  docker pull bkimminich/juice-shop || true
  docker run -d --name lab-juice -p 127.0.0.1:3000:3000 \
    --restart unless-stopped bkimminich/juice-shop || true
  ok "$BB/lab/dvd" || git clone --depth 1 \
    https://github.com/crytic/damn-vulnerable-defi "$BB/lab/dvd" || true
  ok "$BB/run/xbow-validation-benchmarks" || git clone --depth 1 \
    https://github.com/KeygraphHQ/xbow-validation-benchmarks \
    "$BB/run/xbow-validation-benchmarks" || true
}

verify(){
  say "verify"
  for s in "$BB"/glue/*.sh; do bash -n "$s" && echo "ok $s"; done
  "$BB/run/venv/bin/python" -c "import yaml,websockets; print('venv ok')" || true
  (cd "$BB/compose" && docker compose config -q && echo "compose ok")
  curl -fsS -m5 http://127.0.0.1:4000/health/liveliness >/dev/null 2>&1 \
    && echo "litellm UP" || echo "litellm down"
  systemctl --user list-timers 'bb-*' --no-pager 2>/dev/null || true
}

for f in "$@"; do case ${f#--} in
  deps|models|stack|dojo|rengine|agents|units|lab|verify) ${f#--};;
  *) echo "unknown phase $f"; exit 1;; esac; done
[[ $# -eq 0 ]] && echo "usage: bootstrap.sh --deps --models --stack --dojo --rengine --agents --units --lab --verify"
