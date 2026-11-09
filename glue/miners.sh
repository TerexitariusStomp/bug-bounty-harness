#!/usr/bin/env bash
# miners — daily skipped-coverage layer: secrets, cloud, JS/param mining,
# archive diffs. Outputs land in run/dojo-inbox + run/ for agents.
set -euo pipefail; BB_TAG=miners; . "$(dirname "$0")/bb-lib.sh"
mkdir -p "$BB_RUN_DIR/dojo-inbox" "$BB_RUN_DIR/miners"
D=$(date +%F)

iter_programs | while IFS=$'\t' read -r prog dom; do
  host=${dom#\*.}; host=${host%%:*}; is_oos "$prog" "$host" && continue

  # secrets in org repos (orgs listed per-program)
  python3 - "$BB_ROOT/scope/targets.yaml" "$prog" <<'PY' | while read -r org; do
import sys,yaml
p=[x for x in yaml.safe_load(open(sys.argv[1]))["programs"] if x["name"]==sys.argv[2]][0]
for o in p.get("github_orgs") or []: print(o)
PY
    trufflehog github --org="$org" --json 2>/dev/null \
      > "$BB_RUN_DIR/dojo-inbox/truffle-$org-$D.json" || true
  done

  # cloud buckets / asn
  cloud_enum -k "$host" -l "$BB_RUN_DIR/miners/cloud-$host-$D.txt" 2>/dev/null || true
  asnmap -d "$host" -silent 2>/dev/null | anew -q "$BB_RUN_DIR/asn-$prog.txt" || true

  # JS endpoint + secrets AST mining on katana output if present
  KOUT="$BB_RUN_DIR/katana-$host.txt"
  [[ -f $KOUT ]] || katana -u "https://$host" -silent -o "$KOUT" 2>/dev/null || true
  grep -i '\.js' "$KOUT" 2>/dev/null | head -200 | while read -r js; do
    curl -fsS -m10 "$js" -o "$BB_RUN_DIR/miners/tmp.js" 2>/dev/null || continue
    jsluice urls "$BB_RUN_DIR/miners/tmp.js" 2>/dev/null \
      | jq -r '.url' | anew -q "$BB_RUN_DIR/miners/endpoints-$host.txt" || true
    jsluice secrets "$BB_RUN_DIR/miners/tmp.js" 2>/dev/null \
      | anew -q "$BB_RUN_DIR/miners/secrets-$host.json" || true
  done

  # wayback archive diff
  gau "$host" 2>/dev/null | anew -q "$BB_RUN_DIR/miners/wayback-$host.txt" || true
done
log "miners pass complete"
