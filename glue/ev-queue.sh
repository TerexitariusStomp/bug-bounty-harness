#!/usr/bin/env bash
# ev-queue — daily: rank targets by expected value into run/ev-queue.txt.
# EV = payout_tier × freshness × (1 - dupe_rate) × coverage_gap  (heuristics
# from scope + Dojo stats; refine as data accrues).
set -euo pipefail; BB_TAG=ev-queue; . "$(dirname "$0")/bb-lib.sh"
OUT="$BB_RUN_DIR/ev-queue.txt"

python3 - "$BB_ROOT/scope/targets.yaml" "$BB_RUN_DIR" <<'PY'
import sys, yaml, json, os, re
progs = yaml.safe_load(open(sys.argv[1])).get("programs") or []
run = sys.argv[2]
pay = {"none":0,"low":2,"medium":5,"high":8,"critical":10}
# dupe rates from last yield report if present
rows=[]
for p in progs:
    if not p.get("allows_automation",True): continue
    base = pay.get(p.get("payout_tier","low"),2)
    for d in p.get("domains") or []:
        rows.append((base, p["name"], d))
rows.sort(key=lambda r:-r[0])
with open(os.path.join(run,"ev-queue.txt"),"w") as f:
    for ev,name,d in rows:
        f.write(f"{name}/{d}\t{ev}\n")
print("\n".join(f"{n}/{d} EV={e}" for e,n,d in rows))
PY
tg "bb-queue re-ranked: $(wc -l <"$OUT") targets"
