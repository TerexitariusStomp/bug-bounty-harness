#!/usr/bin/env python3
"""sync.py — bounty opportunity index. Feeds → index.yaml → priority queue.

Feeds: bounty-targets-data (repo clone, MIT) → program scopes/meta;
disclose/diodb program-list.json (CC0) → safe-harbor maturity;
bounty/seeds.yaml → live targets + beginner-fit scores from the megaplan.
State machine: candidate→policy_read→recon_done→hunting→report_drafted→
submitted→paid|duped|na→archived. WIP=1 enforced on emit.
priority = 0.4*speed + 0.3*(10-competition) + 0.3*fit   (all 0-10)
"""
import json, os, sys, urllib.request, yaml
from datetime import datetime, timezone

B = os.path.dirname(os.path.abspath(__file__))
IDX = f"{B}/index.yaml"; SEEDS = f"{B}/seeds.yaml"
BTD = f"{B}/data/bounty-targets-data"; QUEUE = f"{B}/queue.txt"
DIODB_URL = "https://raw.githubusercontent.com/disclose/diodb/master/program-list.json"

def load_diodb():
    try:
        d = json.load(urllib.request.urlopen(DIODB_URL, timeout=30))
        # diodb list: [{program_name, safe_harbor, ...}]
        return { (p.get("program_name") or "").lower(): p for p in d }
    except Exception as e:
        print(f"diodb fetch failed: {e}", file=sys.stderr); return {}

def btd_programs():
    """Yield (platform, program-dict) from bounty-targets-data repo."""
    out = []
    for root, _, files in os.walk(os.path.join(BTD, "data")):
        for fn in files:
            if not fn.endswith(".json"): continue
            plat = fn[:-5]
            try:
                data = json.load(open(os.path.join(root, fn)))
            except Exception: continue
            items = data if isinstance(data, list) else data.get("programs") or [data]
            for p in items if isinstance(items, list) else []:
                if isinstance(p, dict): out.append((plat, p))
    return out

def scope_size(p):
    """Rough in-scope asset count from common bounty-targets-data shapes."""
    for k in ("targets", "scope", "in_scope"):
        v = p.get(k)
        if isinstance(v, list): return len(v)
        if isinstance(v, dict): return len(v.get("in_scope") or v)
    return 0

def upsert(idx, name, **fields):
    e = idx.setdefault(name, {"name": name, "state": "candidate", "history": []})
    for k, v in fields.items():
        if v is not None: e[k] = v
    return e

def main():
    idx = yaml.safe_load(open(IDX)) if os.path.exists(IDX) else {}
    diodb = load_diodb()

    # 1. bounty-targets-data → update scope/meta on existing + discover new
    seen = 0
    for plat, p in btd_programs():
        name = p.get("name") or p.get("handle") or p.get("program_name")
        if not name: continue
        key = f"{plat}:{name}"
        seen += 1
        e = upsert(idx, key, platform=plat, handle=name,
                   url=p.get("url") or p.get("policy_url"),
                   scope_assets=scope_size(p),
                   payout_max=p.get("max_bounty") or p.get("bounty_max"))
        sh = diodb.get(str(name).lower()) or diodb.get(str(p.get("handle","")).lower())
        if sh: e["diodb_safe_harbor"] = sh.get("safe_harbor") or sh.get("safeguards_level")

    # 2. seeds (plan's live targets) — authoritative scores
    for s in (yaml.safe_load(open(SEEDS)) or {}).get("targets") or []:
        e = upsert(idx, s["key"], **{k: v for k, v in s.items() if k != "key"})
        if "first_seen" not in e: e["first_seen"] = s.get("first_seen")

    # 3. score + queue
    for e in idx.values():
        sp = float(e.get("speed") or 5); co = float(e.get("competition") or 5)
        fit = float(e.get("fit") or 5)
        e["priority"] = round(0.4*sp + 0.3*(10-co) + 0.3*fit, 2)
    ordered = sorted(idx.values(), key=lambda e: -(e.get("priority") or 0))
    wip = 0
    with open(QUEUE, "w") as f:
        for e in ordered:
            if e.get("state") in ("paid","duped","na","archived"): continue
            if e.get("state") == "hunting": wip += 1
            f.write(f"{e['priority']:.2f}\t{e['name']}\t{e.get('state','?')}"
                    f"\t${e.get('payout_max') or '?'}\tscope:{e.get('scope_assets') or '?'}\n")
    yaml.safe_dump(idx, open(IDX,"w"), sort_keys=False)
    print(f"{len(idx)} programs indexed ({seen} feed items, "
          f"{len(diodb)} diodb), queue={len(ordered)}, hunting-wip={wip}")
    print("top 5:")
    for e in ordered[:5]:
        print(f"  {e['priority']:.2f}  {e['name']:<35} {e.get('state')}")

if __name__ == "__main__":
    main()
