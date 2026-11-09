#!/usr/bin/env bash
# run_recon.sh <domain> — thin chain of installed OSS tools.
# Everything lands in ./recon/<domain>/. ~50 lines as per the plan budget.
set -euo pipefail
export PATH="$HOME/go/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
D="${1:?usage: run_recon.sh <domain>}"; O="recon/$D"; mkdir -p "$O"

subfinder -d "$D" -all -silent -o "$O/subs.txt"
amass enum -passive -d "$D" 2>/dev/null | anew -q "$O/subs.txt" || true
dnsx -l "$O/subs.txt" -silent -o "$O/resolved.txt" || true
httpx -l "$O/resolved.txt" -silent -sc -title -td -o "$O/live.txt" || true
naabu -l "$O/resolved.txt" -top-ports 1000 -silent -o "$O/ports.txt" || true
cut -d' ' -f1 "$O/live.txt" | sed 's|https\?://||' | sort -u > "$O/hosts.txt"

katana -u "https://$D" -silent -o "$O/katana.txt" || true
gau "$D" 2>/dev/null | anew -q "$O/wayback.txt" || true
grep -i '\.js' "$O/katana.txt" 2>/dev/null | while read -r js; do
  curl -fsS -m10 "$js" -o "$O/tmp.js" 2>/dev/null || continue
  jsluice urls "$O/tmp.js" | jq -r '.url' | anew -q "$O/js-endpoints.txt" || true
  jsluice secrets "$O/tmp.js" | anew -q "$O/js-secrets.json" || true
  retire --path "$O/tmp.js" --outputformat json 2>/dev/null | anew -q "$O/retire.json" || true
done

arjun -u "https://$D" -oT "$O/params.txt" 2>/dev/null || true
nuclei -l "$O/hosts.txt" -rl 80 -silent -jle -o "$O/nuclei.jsonl" || true
dalfox file <(printf 'https://%s\n' "$D") -o "$O/xss.txt" 2>/dev/null || true

echo "== done: $O"
echo "subs $(wc -l <"$O/subs.txt" 2>/dev/null) live $(wc -l <"$O/live.txt" 2>/dev/null) nuclei $(wc -l <"$O/nuclei.jsonl" 2>/dev/null)"
