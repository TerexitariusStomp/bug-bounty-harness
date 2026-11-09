#!/usr/bin/env bash
# yield-report — weekly: per-tool hit/FP rates from Dojo → quarantine
# stagnant templates. The anti-stagnation guarantee.
set -euo pipefail; BB_TAG=yield-report; . "$(dirname "$0")/bb-lib.sh"
need curl; need jq
[[ -n "${DOJO_API_TOKEN:-}" ]] || exit 0

curl -fsS "${DOJO_URL:-http://127.0.0.1:8080}/api/v2/findings/?limit=5000" \
  -H "Authorization: Token $DOJO_API_TOKEN" >"$BB_RUN_DIR/findings.json"

python3 - "$BB_RUN_DIR/findings.json" "$BB_INTEL/quarantine" <<'PY'
import json, sys, collections, os
data = json.load(open(sys.argv[1]))
qdir = sys.argv[2]
stats = collections.defaultdict(lambda: [0,0])  # tool -> [active, fp]
for f in data.get("results", []):
    t = f.get("found_by") or f.get("test",{}).get("test_type",{}).get("name","?")
    fp = f.get("false_p") or f.get("out_of_scope")
    stats[str(t)][fp and 1 or 0] += 1
out = ["# yield report", "| tool | active | fp | fp% |", "|---|---|---|---|"]
for t,(a,fp) in sorted(stats.items()):
    pct = 100*fp/max(1,a+fp); out.append(f"| {t} | {a} | {fp} | {pct:.0f}% |")
    if a+fp > 20 and pct > 80:
        open(os.path.join(qdir,"stagnant.txt"),"a").write(t+"\n")
open(os.path.join(qdir,"yield-report.md"),"w").write("\n".join(out)+"\n")
print("\n".join(out))
PY
git -C "$BB_INTEL" add -A && git -C "$BB_INTEL" -c user.email=bb@local \
  -c user.name=bb-lab commit -qm "yield: $(date +%F)" || true
tg "bb-lab weekly yield report written to intel/quarantine/yield-report.md"
