#!/usr/bin/env bash
# strix-feed — route prioritized targets to the agent lanes.
#   source-available → Shannon (white-box)  |  opaque → Strix (black-box)
# High-EV targets (from bb-queue) get an ensemble second pass via pwnkit.
set -euo pipefail; BB_TAG=strix-feed; . "$(dirname "$0")/bb-lib.sh"
QUEUE="$BB_RUN_DIR/ev-queue.txt"; SRC_OK="$BB_RUN_DIR/src-available.txt"
touch "$QUEUE" "$SRC_OK"
export OPENAI_BASE_URL="${LITELLM_BASE:-http://127.0.0.1:4000}/v1"
export OPENAI_API_KEY="${LITELLM_MASTER_KEY:-sk-bb-local-change-me}"
# Strix is litellm-native: model alias resolves through our router
export STRIX_LLM="${STRIX_LLM:-openai/tier-b}"
export STRIX_API_TYPE=chat_completions
export LLM_API_KEY="$OPENAI_API_KEY"
export LLM_API_BASE="$OPENAI_BASE_URL"

while IFS=$'\t' read -r target ev; do
  [[ -z $target ]] && continue
  prog=${target%%/*}; host=${target#*/}
  is_oos "$prog" "$host" && { log "OOS skip: $host"; continue; }

  if grep -qxF "$host" "$SRC_OK" && [[ -x "$BB_RUN_DIR/shannon/shannon" ]]; then
    log "white-box lane: $host"
    # shannon needs -u url and -r repo path (recovered source if present,
    # else the program's public repo mirror under run/repos/)
    repo="$BB_RUN_DIR/recovered-src/$host"
    [[ -d $repo ]] || repo="$BB_RUN_DIR/repos/$host"
    [[ -d $repo ]] || { log "no source for $host — falling to black-box"; repo=""; }
    if [[ -n $repo ]]; then
      (cd "$BB_RUN_DIR/shannon" && timeout 3h ./shannon start -u "https://$host" -r "$repo" \
         --models-config "$BB_RUN_DIR/shannon/models.json" -y \
         > "$BB_RUN_DIR/evidence/shannon-$host-$(date +%s).log" 2>&1) || true
      continue
    fi
  elif command -v strix >/dev/null; then
    log "black-box lane: $host"
    turl=$host; [[ $turl == *://* ]] || turl="http://$turl"
    timeout 3h strix --target "$turl" --non-interactive \
      > "$BB_RUN_DIR/evidence/strix-$host-$(date +%s).log" 2>&1 || true
  else
    log "no agent available for $host"
  fi

  # ensemble second pass on EV >= 8 — second strix run on the other tier
  # (pwnkit repo vanished upstream; model diversity is the ensemble signal)
  if [[ ${ev%.*} -ge 8 ]] && command -v strix >/dev/null; then
    log "ensemble pass: $host"
    ALT=tier-a; [[ $STRIX_LLM == *tier-a* ]] && ALT=tier-b
    STRIX_LLM="openai/$ALT" timeout 2h strix --target "$host" --non-interactive \
      > "$BB_RUN_DIR/evidence/ens-$host-$(date +%s).log" 2>&1 || true
  fi
done < "$QUEUE"
"$BB_ROOT/glue/dojo-sync.sh" || true
