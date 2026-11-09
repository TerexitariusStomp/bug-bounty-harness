#!/usr/bin/env bash
# intel-ingest — 4h: fetch disclosure/research feeds → Tier-A distills into
# candidate artifacts (templates, playbook entries, wordlist rules) in intel/.
set -euo pipefail; BB_TAG=intel-ingest; . "$(dirname "$0")/bb-lib.sh"
FEEDS="$BB_RUN_DIR/feeds.txt"; SEEN="$BB_RUN_DIR/.feed-seen"; touch "$SEEN"
cat >"$FEEDS" <<'EOF'
https://hackerone.com/hacktivity.atom
https://portswigger.net/research/rss
https://blog.projectdiscovery.io/rss/
EOF

NEW=""
while read -r url; do
  [[ -z $url ]] && continue
  curl -fsS -m 20 "$url" 2>/dev/null | python3 -c '
import re,sys
raw=sys.stdin.read()
for t in re.findall(r"<title[^>]*>(.*?)</title>", raw)[:15]:
    t=re.sub(r"<!\[CDATA\[|\]\]>","",t).strip()
    if t: print(t)
' | while read -r title; do
    grep -qxF "$title" "$SEEN" || { echo "$title" >>"$SEEN"; echo "$title"; }
  done
done <"$FEEDS" >"$BB_RUN_DIR/.feed-new"
NEW=$(cat "$BB_RUN_DIR/.feed-new"); [[ -z $NEW ]] && exit 0
log "$(wc -l <"$BB_RUN_DIR/.feed-new") new intel items"

# Tier-A distills: which items are actionable, and as what artifact?
RESP=$(llm tier-a "You maintain a bug-bounty methodology knowledge base.
For each item below reply one line: TEMPLATE|PLAYBOOK|WORDLIST|SKIP<TAB>one-line gist.
Only mark TEMPLATE for concrete reproducible techniques.
Items:
$NEW" || true)
[[ -z $RESP ]] && { log "llm distillation unavailable"; exit 0; }

echo "$RESP" | while IFS=$'\t' read -r kind gist; do
  [[ -z $gist ]] && continue
  case $kind in
    TEMPLATE)  echo "## $gist" >>"$BB_INTEL/templates/candidates.md";;
    PLAYBOOK)  echo "- $gist" >>"$BB_INTEL/playbooks/ingested.md";;
    WORDLIST)  echo "$gist" >>"$BB_INTEL/wordlists/ingested.txt";;
  esac
done
git -C "$BB_INTEL" add -A && git -C "$BB_INTEL" -c user.email=bb@local \
  -c user.name=bb-lab commit -qm "ingest: $(date +%F)" || true
log "distilled → intel/"
