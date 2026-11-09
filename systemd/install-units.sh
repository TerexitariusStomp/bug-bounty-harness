#!/usr/bin/env bash
# install-units.sh — write + enable bb-lab systemd user units.
set -euo pipefail
UDIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
BB="${BB_ROOT:-$HOME/bb-lab}"
BB_RUN_VENV="$BB/run/venv"   # python venv (websockets, yaml) from bootstrap --deps
mkdir -p "$UDIR"

unit() { cat >"$UDIR/$1"; }
svc() { unit "$1" <<EOF
[Service]
Type=oneshot
Environment=BB_ROOT=$BB
ExecStart=$2
EOF
unit "${1%.service}.timer" <<EOF
[Unit]
Description=bb-lab $3
[Timer]
$4
Persistent=true
[Install]
WantedBy=timers.target
EOF
}

svc bb-templatewatch.service "$BB/glue/template-watch.sh" \
    "nuclei template watcher" "OnCalendar=*:0/15"
svc bb-miners.service       "$BB/glue/miners.sh" \
    "secrets/cloud/js miners" "OnCalendar=daily"
svc bb-source.service       "$BB/glue/source-acquire.sh" \
    "source acquisition" "OnCalendar=daily"
svc bb-web3.service         "$BB/glue/web3-scan.sh" \
    "web3 static analysis" "OnCalendar=*-*-* 02:00"
svc bb-fuzz.service         "$BB/glue/web3-scan.sh --fuzz" \
    "contract fuzz campaigns" "OnCalendar=Sun *-*-* 04:00"
svc bb-sync.service         "$BB/glue/dojo-sync.sh --from-rengine" \
    "dojo importer" "OnCalendar=hourly"
svc bb-intel.service        "$BB/glue/intel-ingest.sh" \
    "intel ingestion" "OnCalendar=*-*-* 00,04,08,12,16,20:00"
svc bb-update.service       "$BB/glue/canary-update.sh" \
    "canary toolchain update" "OnCalendar=*-*-* 06:00"
svc bb-analytics.service    "$BB/glue/yield-report.sh" \
    "yield analytics" "OnCalendar=Mon *-*-* 05:00"
svc bb-bench.service        "$BB/glue/bench-run.sh" \
    "harness self-benchmark" "OnCalendar=Sun *-*-* 06:00"
svc bb-queue.service        "$BB/glue/ev-queue.sh" \
    "EV target ranking" "OnCalendar=*-*-* 07:00"
svc bb-strix.service        "$BB/glue/strix-feed.sh" \
    "agent feed dispatch" "OnCalendar=*-*-* 09,21:00"
svc bb-forge.service        "$BB/glue/template-forge.sh" \
    "confirmed-finding template forge" "OnCalendar=*-*-* 10,22:00"
svc bb-chain.service        "$BB/glue/chain-synth.sh" \
    "exploit-chain synthesis" "OnCalendar=*-*-* 08:30"
svc bb-coverage.service     "$BB/glue/coverage.sh" \
    "coverage accounting" "OnCalendar=Sun *-*-* 05:00"

unit bb-edge.service <<EOF
[Service]
Environment=BB_ROOT=$BB
ExecStart=$BB_RUN_VENV/bin/python $BB/glue/edge-watch.py
Restart=always
RestartSec=30
EOF

# llama.cpp tier-b server — CUDA build, full GPU offload (-ngl 99)
unit bb-llama.service <<'EOF'
[Service]
EnvironmentFile=%h/bb-lab/.env
ExecStart=/bin/sh -c '%h/llama.cpp/build-cuda/bin/llama-server -m "$${BB_TIERB_MODEL:-%h/.hermes/models/Ornith-1.5-9B-uncensored.Q4_K_M.gguf}" --host 0.0.0.0 --port 8390 -c 32768 -ngl 99'
Restart=always
RestartSec=10
EOF

systemctl --user daemon-reload
for t in bb-{templatewatch,miners,source,web3,fuzz,sync,intel,update,analytics,bench,queue,strix}.timer bb-{edge,llama}.service; do
  systemctl --user enable --now "$t" 2>/dev/null && echo "enabled $t" || echo "SKIP $t"
done
systemctl --user list-timers 'bb-*' --no-pager
