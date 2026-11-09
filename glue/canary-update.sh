#!/usr/bin/env bash
# canary-update — daily: update toolchain → smoke-test on lab → promote or
# rollback. Keeps tools bleeding-edge without broken pipelines.
set -euo pipefail; BB_TAG=canary-update; . "$(dirname "$0")/bb-lib.sh"
need docker

SMOKE="$BB_ROOT/glue/bench-run.sh --quick"
UPDATED=()

if command -v pdtm >/dev/null; then
  pdtm -update-all -silent >>"$BB_LOG_DIR/$BB_TAG.log" 2>&1 && UPDATED+=(pdtm-tools)
fi
( cd "$BB_ROOT/compose" && docker compose pull -q \
    >>"$BB_LOG_DIR/$BB_TAG.log" 2>&1 ) && UPDATED+=(compose) || true

((${#UPDATED[@]})) || { log "nothing to update"; exit 0; }
log "updated: ${UPDATED[*]} — running canary smoke"

if $SMOKE >>"$BB_LOG_DIR/$BB_TAG.log" 2>&1; then
  log "canary PASS — promoted"; tg "bb-lab update: ${UPDATED[*]} OK"
else
  log "canary FAIL — rolling back compose images"
  ( cd "$BB_ROOT/compose" && docker compose down && docker compose up -d \
      --no-deps --force-recreate ) || true
  tg "bb-lab update FAILED smoke — rolled back, check logs"
fi
