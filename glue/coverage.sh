#!/usr/bin/env bash
# coverage — per-program coverage accounting: endpoints tested vs known.
# Output: intel/coverage.md + per-program gap list (hunt gaps, not retreads).
set -euo pipefail; BB_TAG=coverage; . "$(dirname "$0")/bb-lib.sh"
OUT="$BB_INTEL/coverage.md"
{
echo "# coverage $(date +%F)"; echo
echo "| program | known endpoints | tested | % |"; echo "|---|---|---|---|"
} >"$OUT"

iter_programs | cut -f1 -d$'\t' | sort -u | while read -r prog; do
  KNOWN=$(cat "$BB_RUN_DIR/miners"/endpoints-*.txt "$BB_RUN_DIR/miners"/wayback-*.txt \
          "$BB_RUN_DIR"/katana-*.txt 2>/dev/null | sort -u | wc -l)
  TESTED=$(curl -fsS -m20 "${DOJO_URL:-http://127.0.0.1:8085}/api/v2/endpoints/?limit=1000" \
           -H "Authorization: Token ${DOJO_API_TOKEN:-}" 2>/dev/null \
           | python3 -c 'import json,sys; print(json.load(sys.stdin).get("count",0))' 2>/dev/null || echo 0)
  PCT=$(( KNOWN ? TESTED * 100 / KNOWN : 0 ))
  echo "| $prog | $KNOWN | $TESTED | $PCT% |" >>"$OUT"
  log "$prog: $TESTED/$KNOWN tested ($PCT%)"
done
git -C "$BB_INTEL" add -A && git -C "$BB_INTEL" -c user.email=bb@local \
  -c user.name=bb-lab commit -qm "coverage $(date +%F)" || true
