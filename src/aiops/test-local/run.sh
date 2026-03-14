#!/usr/bin/env bash
# Quick-start: source .env and launch AIOps daemon with debug logging
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIOPS_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$(dirname "$AIOPS_DIR")"

# Load env
set -a
source "$SCRIPT_DIR/.env"
set +a

# Activate venv
source "$AIOPS_DIR/.venv/bin/activate"

cd "$SRC_DIR"

echo "Starting AIOps daemon (interval=${AIOPS_HEALTH_CHECK_INTERVAL}s, model=${AIOPS_DAEMON_MODEL})"
echo "  Grafana:      $GRAFANA_URL"
echo "  Alertmanager: $ALERTMANAGER_URL"
echo "  Cluster:      $CLUSTER_NAME"
echo ""
echo "Press Ctrl+C to stop."
echo ""

exec python -m uvicorn aiops.web:app --host 0.0.0.0 --port 8000 --log-level debug
