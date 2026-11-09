#!/usr/bin/env bash
# template-forge — watch Dojo for human-confirmed findings → LLM-generalize
# into reusable nuclei templates → intel/templates + trigger fleet rescan.
# Human-gated: only findings manually marked verified+non-duplicate forge.
set -euo pipefail; BB_TAG=forge; . "$(dirname "$0")/bb-lib.sh"
need curl; need jq; FORGED="$BB_RUN_DIR/.forged"; touch "$FORGED"
[[ -n "${DOJO_API_TOKEN:-}" ]] || exit 0

curl -fsS -m30 "${DOJO_URL:-http://127.0.0.1:8085}/api/v2/findings/?verified=true&limit=200" \
  -H "Authorization: Token $DOJO_API_TOKEN" | jq -r '.results[] |
    select(.duplicate==false) | [.id, .title, (.cwe//""), (.description//"" | .[0:500])] | @tsv' \
| while IFS=$'\t' read -r fid title cwe desc; do
  grep -qxF "$fid" "$FORGED" && continue
  log "forging template for: $title"
  TPL=$(llm tier-a "Write a nuclei v3 YAML template that detects this bug class on ANY host:
TITLE: $title
CWE: $cwe
DETAILS: $desc
Output ONLY the YAML, id: bb-forge-$fid, no prose." | sed 's/^```yaml//;s/^```//')
  [[ ${#TPL} -gt 200 ]] || { log "llm gave unusable template for $fid"; continue; }
  F="$BB_INTEL/templates/bb-forge-$fid.yaml"
  echo "$TPL" > "$F"
  echo "$fid" >>"$FORGED"
  # rescan the fleet with just this template — one bug becomes many
  nuclei -l "$BB_RUN_DIR/alive.txt" -t "$F" -rl "${BB_RATE_LIMIT:-150}" \
    -silent -jle -o "$BB_RUN_DIR/dojo-inbox/forge-$fid.jsonl" 2>/dev/null || true
  tg "bb-forge: '$title' → template $fid, fleet rescan queued"
done
git -C "$BB_INTEL" add -A && git -C "$BB_INTEL" -c user.email=bb@local \
  -c user.name=bb-lab commit -qm "forge $(date +%F)" || true
