#!/usr/bin/env bash
# template-watch — 15-min loop: pull nuclei-templates + cvemap, rescan alive
# hosts against NEW/modified templates only. The speed edge.
set -euo pipefail; BB_TAG=template-watch; . "$(dirname "$0")/bb-lib.sh"
need git; need nuclei; need jq

TDIR="${NUCLEI_TEMPLATES_DIR:-$BB_RUN_DIR/nuclei-templates}"
ALIVE="$BB_RUN_DIR/alive.txt"; STATE="$BB_RUN_DIR/.tpl-last-commit"
[[ -s $ALIVE ]] || { log "no alive host list yet — skipping"; exit 0; }

if [[ ! -d $TDIR/.git ]]; then
  git clone -q --depth 1 https://github.com/projectdiscovery/nuclei-templates "$TDIR"
  git -C "$TDIR" rev-parse HEAD >"$STATE"; log "initial clone done"; exit 0
fi

OLD=$(cat "$STATE" 2>/dev/null || echo "")
git -C "$TDIR" pull -q
NEW=$(git -C "$TDIR" rev-parse HEAD)
[[ $OLD == "$NEW" ]] && exit 0

# changed templates since last pull
mapfile -t CHANGED < <(git -C "$TDIR" diff --name-only "$OLD" "$NEW" \
  | grep -E '\.ya?ml$' || true)
echo "$NEW" >"$STATE"
((${#CHANGED[@]})) || exit 0
log "${#CHANGED[@]} new/modified templates since ${OLD:0:8}"

# fresh CVEs of the day (optional intel)
cvemap -silent -l 20 2>/dev/null >"$BB_RUN_DIR/cvemap-latest.txt" || true

# scan alive hosts with just the delta — first-to-fire wins
OUT="$BB_RUN_DIR/tplwatch-$(date +%s).jsonl"
nuclei -l "$ALIVE" -rl "${BB_RATE_LIMIT:-150}" -silent -jle -o "$OUT" \
  $(printf -- '-t %q ' "${CHANGED[@]}" | tr '\n' ' ') || true

if [[ -s $OUT ]]; then
  HITS=$(wc -l <"$OUT")
  log "$HITS hits on new templates"
  "$BB_ROOT/glue/dojo-sync.sh" --file "$OUT" --type "Nuclei Scan" || true
  [[ $HITS -gt 0 ]] && tg "bb-lab: $HITS hits on ${#CHANGED[@]} fresh nuclei templates — see Dojo"
fi
