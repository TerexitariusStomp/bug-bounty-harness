#!/usr/bin/env bash
# dojo-sync — import scan files into DefectDojo + pull new reNgine findings.
# Usage: dojo-sync.sh [--file X --type "Nuclei Scan"] [--from-rengine]
set -euo pipefail; BB_TAG=dojo-sync; . "$(dirname "$0")/bb-lib.sh"
need curl; need jq
[[ -n "${DOJO_API_TOKEN:-}" ]] || die "DOJO_API_TOKEN unset"

import_file() {  # <file> <scan_type> <engagement-name>
  local file=$1 stype=$2 eng=$3
  curl -fsS -m 300 "${DOJO_URL:-http://127.0.0.1:8080}/api/v2/import-scan/" \
    -H "Authorization: Token $DOJO_API_TOKEN" \
    -F "scan_type=$stype" -F "file=@$file" -F "engagement_name=$eng" \
    -F "product_name=bb-lab" -F "product_type_name=bb-program" \
    -F "auto_create_context=true" -F "deduplication_on_engagement=true" \
    | jq -r '"imported: test=\(.test // .id)"' | tee -a "$BB_LOG_DIR/$BB_TAG.log"
}

FILE=""; TYPE="Nuclei Scan"; FROM_RENGINE=0
while (($#)); do case $1 in
  --file) FILE=$2; shift 2;; --type) TYPE=$2; shift 2;;
  --from-rengine) FROM_RENGINE=1; shift;; *) shift;; esac; done

if [[ -n $FILE ]]; then
  import_file "$FILE" "$TYPE" "bb-auto-$(date +%F)"
fi

# drop-folder path: anything placed in run/dojo-inbox/ gets imported
for f in "$BB_RUN_DIR/dojo-inbox"/*; do
  [[ -f $f ]] || continue
  case $f in *.sarif) T="SARIF";; *) T="Nuclei Scan";; esac
  import_file "$f" "$T" "bb-auto-$(date +%F)" && mv "$f" "$f.imported"
done

# reNgine pull: export latest scan vulnerabilities via its API if reachable
if ((FROM_RENGINE)) && [[ -n "${RENGINE_USER:-}" ]]; then
  curl -fsS -m 60 -u "$RENGINE_USER:$RENGINE_PASS" \
    "${RENGINE_URL:-https://127.0.0.1}/api/vulnerabilities/?format=json" \
    -k -o "$BB_RUN_DIR/rengine-vulns.json" 2>/dev/null \
    && log "pulled reNgine vulns" || log "reNgine API unreachable"
fi

# alert on new high/critical unique findings (from last import summary)
tg "$(basename "$0") ran: $(date +%F\ %H:%M)" 2>/dev/null || true
