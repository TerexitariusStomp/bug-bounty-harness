#!/usr/bin/env bash
# chain-synth — compose single findings into exploit-chain hypotheses on
# high-EV hosts, then hand the hypothesis to the agent lanes for PoC.
set -euo pipefail; BB_TAG=chain-synth; . "$(dirname "$0")/bb-lib.sh"
[[ -n "${DOJO_API_TOKEN:-}" ]] || exit 0

# group active findings by host, then ask Tier-A for viable chains
curl -fsS -m30 "${DOJO_URL:-http://127.0.0.1:8085}/api/v2/findings/?active=true&limit=1000" \
  -H "Authorization: Token $DOJO_API_TOKEN" >"$BB_RUN_DIR/f.json"

python3 - "$BB_RUN_DIR/f.json" <<'PY' >"$BB_RUN_DIR/chain-candidates.txt"
import json,sys,collections
d=json.load(open(sys.argv[1])); by={}
for f in d.get("results",[]):
    h=(f.get("endpoints") or [{}])[0].get("host") or "?"
    by.setdefault(h,[]).append(f["title"][:80])
for h,ts in by.items():
    if len(ts)>=2: print(h+"\t"+" | ".join(ts[:12]))
PY

while IFS=$'\t' read -r host titles; do
  CHAIN=$(llm tier-a "Bug-bounty findings on $host: $titles
Suggest ONE concrete exploit chain (e.g., SSRF->metadata->creds, IDOR+misconfig->ATO).
Reply 'none' if no plausible chain. One paragraph max, actionable steps." || true)
  [[ -z $CHAIN || $CHAIN == none* ]] && continue
  log "chain hypothesis on $host: ${CHAIN:0:120}"
  grep -qxF "$host" "$BB_RUN_DIR/ev-queue.txt" || echo "chain/$host	9" >>"$BB_RUN_DIR/ev-queue.txt"
  tg "bb-chain on $host: ${CHAIN:0:300}"
done <"$BB_RUN_DIR/chain-candidates.txt"
