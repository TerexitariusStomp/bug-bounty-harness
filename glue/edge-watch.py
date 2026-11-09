#!/usr/bin/env python3
"""edge-watch — continuous daemon: real-time CT-log stream (certstream)
+ git-watch on in-scope org repos. New assets → trigger rescan via
reNgine event engine + append to strix feed queue. Deps: websockets, PyYAML.
"""
import asyncio, json, os, re, sys, time, urllib.request, subprocess

import yaml, websockets  # noqa: E401 — installed by bootstrap --deps

BB = os.path.expanduser(os.environ.get("BB_ROOT", "~/bb-lab"))
RUN = f"{BB}/run"; LOG = open(f"{BB}/logs/edge-watch.log", "a")
ENV = dict(l.split("=",1) for l in open(f"{BB}/.env") if "=" in l and not l.startswith("#"))
env = {k.strip(): v.strip() for k,v in ENV.items()}

def log(msg): print(f"[{time.strftime('%F %T')}] edge {msg}", file=LOG, flush=True)
def tg(msg):
    tok, chat = env.get("TELEGRAM_BOT_TOKEN"), env.get("TELEGRAM_CHAT_ID")
    if not tok: return
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{tok}/sendMessage",
        data=f"chat_id={chat}&text={msg}".encode())
    try: urllib.request.urlopen(req, timeout=10)
    except Exception as e: log(f"tg fail {e}")

def scope():
    d = yaml.safe_load(open(f"{BB}/scope/targets.yaml"))
    suffixes, oos, orgs = [], [], []
    for p in d.get("programs") or []:
        if not p.get("allows_automation", True): continue
        suffixes += [x.lstrip("*.").split(":")[0] for x in p.get("domains") or []]
        oos += [re.compile(r) for r in p.get("out_of_scope_regex") or []]
        orgs += p.get("github_orgs") or []
    return suffixes, oos, orgs

SUFFIXES, OOS, ORGS = scope()

def in_scope(name):
    if any(r.search(name) for r in OOS): return False
    return any(name == s or name.endswith("."+s) for s in SUFFIXES)

def fire(host, why):
    log(f"NEW {host} ({why})"); tg(f"bb-lab new asset: {host} ({why})")
    with open(f"{RUN}/edge-new.txt","a") as f: f.write(host+"\n")
    with open(f"{RUN}/ev-queue.txt","a") as f: f.write(f"edge/{host}\t7\n")

async def ct_stream():
    url = "wss://certstream.calidog.io/"
    while True:
        try:
            async with websockets.connect(url, ping_interval=15) as ws:
                log("certstream connected")
                async for msg in ws:
                    try:
                        m = json.loads(msg)
                        names = m.get("data",{}).get("leaf_cert",{}) \
                                  .get("all_domains",[])
                        for n in names:
                            n = n.lstrip("*.")
                            if in_scope(n): fire(n, "ct")
                    except Exception: pass
        except Exception as e:
            log(f"certstream reconnect: {e}"); await asyncio.sleep(30)

async def git_watch():
    tok = env.get("GITHUB_TOKEN","")
    while True:
        for org in ORGS:
            try:
                req = urllib.request.Request(
                    f"https://api.github.com/orgs/{org}/repos?per_page=100",
                    headers={"Authorization": f"Bearer {tok}",
                             "Accept":"application/vnd.github+json"})
                repos = json.load(urllib.request.urlopen(req, timeout=20))
                seen = f"{RUN}/.gitwatch-{org}"
                known = set(open(seen).read().split()) if os.path.exists(seen) else set()
                for r in repos:
                    if r["name"] not in known and known:
                        fire(f"{org}/{r['name']}", "new-repo")
                    known.add(r["name"])
                open(seen,"w").write("\n".join(sorted(known)))
            except Exception as e: log(f"gitwatch {org}: {e}")
        await asyncio.sleep(900)  # 15 min

async def main():
    await asyncio.gather(ct_stream(), git_watch())

if __name__ == "__main__":
    asyncio.run(main())
