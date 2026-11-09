#!/usr/bin/env bash
# bench-run — score the whole harness on public agent benchmarks; regression
# gate for evolution changes. --quick = small smoke subset (canary uses it).
set -euo pipefail; BB_TAG=bench-run; . "$(dirname "$0")/bb-lib.sh"
QUICK=0; [[ "${1:-}" == "--quick" ]] && QUICK=1
BENCH="$BB_RUN_DIR/xbow-validation-benchmarks"
HIST="$BB_INTEL/bench-history"; RES="$HIST/latest.score"

if [[ ! -d $BENCH/.git ]]; then
  git clone -q --depth 1 \
    https://github.com/KeygraphHQ/xbow-validation-benchmarks "$BENCH" \
    || { log "bench repo unavailable"; exit 0; }
fi

# quick smoke = is the harness alive end-to-end? (lab + agent reachable)
if ((QUICK)); then
  curl -fsS -m5 "${LITELLM_BASE:-http://127.0.0.1:4000}/health/liveliness" \
    >/dev/null || die "litellm down"
  curl -fsS -m5 "${DOJO_URL:-http://127.0.0.1:8080}/login" >/dev/null \
    || log "dojo down (non-fatal for canary)"
  command -v nuclei >/dev/null || die "nuclei missing after update"
  log "smoke OK"; exit 0
fi

# full weekly bench — run N challenges through Strix, record solve rate
N=5   # keep cheap by default; raise for real scoring
SCORE=0; TOTAL=0
for d in "$BENCH"/benchmarks/XBEN-*/ ; do
  ((TOTAL>=N)) && break
  name=$(basename "$d")
  if command -v strix >/dev/null && [[ -f $d/docker-compose.yml ]]; then
    # repo convention: make build/run BENCHMARK=XBEN-XXX-24 (prints URL+port)
    URL=$(make -s -C "$BENCH" run BENCHMARK="$name" 2>/dev/null \
          | grep -oE 'http://[^ ]+' | head -1)
    [[ -z $URL ]] && { log "$name deploy failed"; continue; }
    timeout 20m strix --target "$URL" --non-interactive \
      >"$BB_RUN_DIR/bench-$name.log" 2>&1 \
      && grep -qi "flag{" "$BB_RUN_DIR/bench-$name.log" && ((SCORE++)) || true
    (cd "$d" && docker compose down -v 2>/dev/null) || true
  fi
  ((TOTAL++))
done
echo "$(date +%F) $SCORE/$TOTAL" | tee "$RES"
git -C "$BB_INTEL" add -A && git -C "$BB_INTEL" -c user.email=bb@local \
  -c user.name=bb-lab commit -qm "bench $(date +%F): $SCORE/$TOTAL" || true
tg "bb-lab bench: $SCORE/$TOTAL solved"
