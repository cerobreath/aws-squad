#!/usr/bin/env bash
# AIOps local test setup — deploys observability stack + failing pods on minikube
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIOPS_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$(dirname "$AIOPS_DIR")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*"; }

# ---------- Pre-flight ----------
info "Checking prerequisites..."
for cmd in kubectl minikube; do
    command -v "$cmd" &>/dev/null || { error "$cmd not found"; exit 1; }
done

minikube status &>/dev/null || { error "minikube not running — start with: minikube start"; exit 1; }
info "Minikube is running"

# ---------- Helm (local install if missing) ----------
if ! command -v helm &>/dev/null; then
    info "Installing helm to ~/.local/bin..."
    mkdir -p "$HOME/.local/bin"
    curl -fsSL https://get.helm.sh/helm-v3.20.1-linux-amd64.tar.gz | tar xzf - -C /tmp
    mv /tmp/linux-amd64/helm "$HOME/.local/bin/helm"
    export PATH="$HOME/.local/bin:$PATH"
fi
info "Helm: $(helm version --short 2>/dev/null)"

# ---------- kube-prometheus-stack ----------
if helm list -n monitoring 2>/dev/null | grep -q kube-prom; then
    info "kube-prometheus-stack already installed"
else
    info "Deploying kube-prometheus-stack..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update
    helm install kube-prom prometheus-community/kube-prometheus-stack \
        --namespace monitoring --create-namespace \
        --set grafana.service.type=NodePort \
        --set grafana.service.nodePort=30080 \
        --set grafana.adminPassword=admin \
        --set alertmanager.enabled=true \
        --set prometheus.prometheusSpec.retention=1d \
        --set prometheus.prometheusSpec.resources.requests.memory=256Mi \
        --set prometheus.prometheusSpec.resources.limits.memory=512Mi \
        --wait --timeout 5m
fi

info "Waiting for monitoring pods..."
kubectl -n monitoring wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana --timeout=120s
kubectl -n monitoring wait --for=condition=Ready pod -l app.kubernetes.io/name=alertmanager --timeout=120s

# ---------- Port-forwards ----------
info "Setting up port-forwards..."
# Kill stale forwards
pkill -f "port-forward.*kube-prom-grafana" 2>/dev/null || true
pkill -f "port-forward.*kube-prom.*alertmanager" 2>/dev/null || true
sleep 1

kubectl -n monitoring port-forward svc/kube-prom-grafana 3001:80 &>/dev/null &
echo $! > /tmp/aiops-grafana-pf.pid
kubectl -n monitoring port-forward svc/kube-prom-kube-prometheus-alertmanager 9093:9093 &>/dev/null &
echo $! > /tmp/aiops-am-pf.pid
sleep 3

# Verify connectivity
curl -sf http://localhost:3001/api/health >/dev/null && info "Grafana reachable at http://localhost:3001" || error "Grafana not reachable"
curl -sf http://localhost:9093/api/v2/status >/dev/null && info "Alertmanager reachable at http://localhost:9093" || error "Alertmanager not reachable"

# ---------- Grafana service account ----------
info "Ensuring Grafana service account..."
SA_SEARCH=$(curl -s "http://localhost:3001/api/serviceaccounts/search?query=aiops" -u admin:admin)
SA_COUNT=$(echo "$SA_SEARCH" | python3 -c "import sys,json; print(json.load(sys.stdin)['totalCount'])" 2>/dev/null || echo 0)

if [ "$SA_COUNT" -eq 0 ]; then
    SA_RESP=$(curl -s -X POST http://localhost:3001/api/serviceaccounts \
        -H "Content-Type: application/json" -u admin:admin \
        -d '{"name":"aiops-daemon","role":"Editor"}')
    SA_ID=$(echo "$SA_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
else
    SA_ID=$(echo "$SA_SEARCH" | python3 -c "import sys,json; print(json.load(sys.stdin)['serviceAccounts'][0]['id'])")
fi

TOKEN_RESP=$(curl -s -X POST "http://localhost:3001/api/serviceaccounts/${SA_ID}/tokens" \
    -H "Content-Type: application/json" -u admin:admin \
    -d "{\"name\":\"aiops-token-$(date +%s)\"}")
TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])" 2>/dev/null || echo "")

if [ -n "$TOKEN" ]; then
    info "Grafana SA token created"
    # Update .env with fresh token
    sed -i "s|^GRAFANA_SERVICE_ACCOUNT_TOKEN=.*|GRAFANA_SERVICE_ACCOUNT_TOKEN=${TOKEN}|" "$SCRIPT_DIR/.env"
else
    warn "Could not create Grafana token (may already exist). Using existing .env value."
fi

# ---------- Deploy failing test pods ----------
info "Deploying failing test pods..."
kubectl apply -f "$SCRIPT_DIR/failing-pod.yaml"
sleep 5
kubectl get pods -n test-aiops -o wide
echo ""

# ---------- Python venv ----------
if [ ! -f "$AIOPS_DIR/.venv/bin/activate" ]; then
    info "Creating Python venv..."
    python3 -m venv "$AIOPS_DIR/.venv"
    "$AIOPS_DIR/.venv/bin/pip" install -q -r "$AIOPS_DIR/requirements.txt" httpx "mcp[cli]" kubectl-mcp-server
fi
info "Python venv ready at $AIOPS_DIR/.venv"

echo ""
info "========================================="
info "  Setup complete!"
info "========================================="
info ""
info "To run AIOps daemon:"
info "  cd $SRC_DIR"
info "  source aiops/.venv/bin/activate"
info "  set -a; source aiops/test-local/.env; set +a"
info "  python -m uvicorn aiops.web:app --host 0.0.0.0 --port 8000 --log-level debug"
info ""
info "Dashboards:"
info "  AIOps UI:      http://localhost:8000"
info "  Grafana:       http://localhost:3001  (admin/admin)"
info "  Alertmanager:  http://localhost:9093"
info ""
info "Check alerts:  curl -s http://localhost:9093/api/v2/alerts | python3 -m json.tool"
info "Check daemon:  curl -s http://localhost:8000/api/daemon/status | python3 -m json.tool"
