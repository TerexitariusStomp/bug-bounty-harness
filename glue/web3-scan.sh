#!/usr/bin/env bash
# web3-scan — nightly: for each repo in contracts.yaml, pull → static
# analysis (slither/aderyn) → SARIF/JSON into dojo-inbox. Fuzz on schedule
# is driven separately (bb-fuzz timer calls this with --fuzz).
set -euo pipefail; BB_TAG=web3-scan; . "$(dirname "$0")/bb-lib.sh"
need git; need docker
mkdir -p "$BB_RUN_DIR/dojo-inbox" "$BB_RUN_DIR/repos"
TOOLBOX=ghcr.io/trailofbits/eth-security-toolbox/ci:nightly
FUZZ=0; [[ "${1:-}" == "--fuzz" ]] && FUZZ=1

python3 - "$BB_ROOT/scope/contracts.yaml" <<'PY' | while IFS=$'\t' read -r name repo ref lang fuzz dirs; do
import sys, yaml
for c in yaml.safe_load(open(sys.argv[1])).get("contracts") or []:
    print("\t".join([c["name"], c["repo"], c.get("ref","main"),
                     c.get("lang","solidity"), str(c.get("fuzz",False)).lower(),
                     ",".join(c.get("dirs") or ["."])]))
PY
  d="$BB_RUN_DIR/repos/$name"; OUT="$BB_RUN_DIR/dojo-inbox/${name}-$(date +%F)"
  if [[ -d $d/.git ]]; then
    git -C "$d" fetch -q origin && git -C "$d" reset -q --hard "origin/$ref"
  else
    git clone -q --depth 1 -b "$ref" "$repo" "$d" || { log "clone failed: $repo"; continue; }
  fi

  case $lang in
    solidity|vyper)
      docker run --rm -v "$d:/src" -w /src "$TOOLBOX" \
        sh -c "slither . --sarif /src/slither.sarif 2>/dev/null; aderyn . -o aderyn.json 2>/dev/null || true" \
        || log "toolbox run failed: $name"
      [[ -f $d/slither.sarif ]] && cp "$d/slither.sarif" "$OUT-slither.sarif"
      [[ -f $d/aderyn.json ]]   && cp "$d/aderyn.json"   "$OUT-aderyn.json"
      if ((FUZZ)) && [[ $fuzz == true ]]; then
        log "fuzz campaign: $name (medusa, 8h cap)"
        timeout 8h docker run --rm -v "$d:/src" -w /src "$TOOLBOX" \
          sh -c 'medusa fuzz --workers 12 2>/dev/null || echidna . --contract Test --config echidna.yaml 2>/dev/null || true' \
          >"$BB_LOG_DIR/fuzz-$name.log" 2>&1 || true
      fi ;;
    rust-solana|rust-near)
      (cd "$d" && cargo audit --json >"$OUT-cargo-audit.json" 2>/dev/null) || true ;;
  esac
  log "done: $name"
done
"$BB_ROOT/glue/dojo-sync.sh" || true
