#!/usr/bin/env bash
# bb-lib.sh — shared helpers for bb-lab glue scripts. Source, don't run.
BB_ROOT="${BB_ROOT:-$HOME/bb-lab}"
BB_LOG_DIR="$BB_ROOT/logs"; BB_RUN_DIR="$BB_ROOT/run"; BB_INTEL="$BB_ROOT/intel"
# systemd units run with a minimal PATH — put the toolchain first
export PATH="$HOME/go/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
mkdir -p "$BB_LOG_DIR" "$BB_RUN_DIR/evidence" "$BB_RUN_DIR/dojo-inbox"
[[ -f "$BB_ROOT/.env" ]] && set -a && . "$BB_ROOT/.env" && set +a

log() { printf '[%s] %s %s\n' "$(date +%F\ %T)" "${BB_TAG:-bb}" "$*" | tee -a "$BB_LOG_DIR/${BB_TAG:-bb}.log"; }
die() { log "FATAL: $*"; exit 1; }
need() { command -v "$1" >/dev/null || die "missing dependency: $1"; }

tg() {  # telegram notify; no-op if unconfigured
  [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] || return 0
  curl -fsS -m 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" --data-urlencode "text=$*" \
    -d disable_web_page_preview=true >/dev/null 2>&1 \
    || log "WARN: telegram send failed"
}

llm() { # llm <tier> <prompt> → completion text via LiteLLM
  need curl; need jq
  curl -fsS -m 300 "${LITELLM_BASE:-http://127.0.0.1:4000}/v1/chat/completions" \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-sk-bb-local-change-me}" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg m "$1" --arg p "$2" \
         '{model:$m,messages:[{role:"user",content:$p}]}')" \
    | jq -r '.choices[0].message.content // empty'
}

# iter_programs — emits "name<TAB>domain" lines for automation-allowed programs
iter_programs() {
  python3 - "$BB_ROOT/scope/targets.yaml" <<'PY'
import sys, yaml
for p in yaml.safe_load(open(sys.argv[1])).get("programs") or []:
    if not p.get("allows_automation", True):
        continue
    for d in p.get("domains") or []:
        print(f"{p['name']}\t{d}")
PY
}

# is_oos <program> <host> → exit 0 (true) if OUT of scope — callers: `is_oos ... && skip`
is_oos() {
  python3 - "$BB_ROOT/scope/targets.yaml" "$1" "$2" <<'PY'
import re, sys, yaml
progs = yaml.safe_load(open(sys.argv[1])).get("programs") or []
p = next((x for x in progs if x["name"] == sys.argv[2]), None)
host = sys.argv[3].split(":")[0].lstrip("*.")
if not p:
    sys.exit(0)  # unknown program → treat as out of scope
doms = [str(d).split(":")[0].lstrip("*.") for d in p.get("domains") or []]
matched = any(host == d or host.endswith("." + d) or d == host for d in doms)
oos = (not matched) or any(re.search(r, host) for r in p.get("out_of_scope_regex") or [])
sys.exit(0 if oos else 1)
PY
}
