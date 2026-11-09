# bounty/ — fastest-cash workspace (plan-2c88ab26561f28a4)

- `sync.py` — opportunity index. Feeds: bounty-targets-data (934 programs), diodb safe-harbor (2432), seeds.yaml (14 live targets). `bounty-sync.timer` runs it daily 06:30.
- `index.yaml` — full DB. `queue.txt` — ranked queue. WIP=1.
- `run_recon.sh <domain>` — subfinder→amass→dnsx→httpx→naabu→katana→gau→jsluice→retire→arjun→nuclei→dalfox, output in `recon/<domain>/`.
- `tools/` LinkFinder, SecretFinder · `wordlists/` SecLists, PATT · `data/` feed clones
- Manual tier: `zaproxy`, `mitmproxy` (installed). Reporting: pandoc.

Top of queue right now: `bugcrowd:klaviyo` (8.10) — the plan's rank-1 pick.
Human steps only you can do: platform accounts + Veriff/W-9 (P0), 25 PortSwigger labs (P1), then hunt from `queue.txt` top-down.
