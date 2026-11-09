#!/usr/bin/env bash
# source-acquire — daily: recover/manufacture source for in-scope hosts;
# promotes recovered targets into the Shannon white-box lane.
set -euo pipefail; BB_TAG=source-acquire; . "$(dirname "$0")/bb-lib.sh"
SRC_OK="$BB_RUN_DIR/src-available.txt"; touch "$SRC_OK"
DEST="$BB_RUN_DIR/recovered-src"; mkdir -p "$DEST"

iter_programs | while IFS=$'\t' read -r prog dom; do
  host=${dom#\*.}; host=${host%%:*}
  is_oos "$prog" "$host" && continue
  url="https://$host"; hdir="$DEST/$host"; mkdir -p "$hdir"

  # .git exposure
  code=$(curl -sk -o /dev/null -w '%{http_code}' --path-as-is \
         "$url/.git/config" -m 10 || true)
  if [[ $code == 200 ]] && command -v git-dumper >/dev/null; then
    log "exposed .git on $host — dumping"
    git-dumper "$url/.git/" "$hdir/git" >>"$BB_LOG_DIR/$BB_TAG.log" 2>&1 \
      && grep -qxF "$host" "$SRC_OK" || echo "$host" >>"$SRC_OK"
  fi

  # webpack sourcemaps (top-level app.js guesses + katana-found if present)
  for sm in "$url/app.js.map" "$url/main.js.map" "$url/static/js/main.js.map"; do
    if curl -fsS -m 10 -o "$hdir/$(basename $sm)" "$sm" 2>/dev/null; then
      log "sourcemap found: $sm"
      grep -qxF "$host" "$SRC_OK" || echo "$host" >>"$SRC_OK"
      command -v sourcemapper >/dev/null && \
        sourcemapper -o "$hdir/mapped" -u "$sm" >>"$BB_LOG_DIR/$BB_TAG.log" 2>&1 || true
      break
    fi
  done

  # github orgs already in scope → repo mirror
  # (orgs parsed inside python for yaml correctness)
done
log "src-available hosts: $(wc -l <"$SRC_OK" 2>/dev/null || echo 0)"
