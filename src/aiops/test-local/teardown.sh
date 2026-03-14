#!/usr/bin/env bash
# Tear down local test environment
set -euo pipefail

echo "[*] Killing port-forwards..."
pkill -f "port-forward.*kube-prom-grafana" 2>/dev/null || true
pkill -f "port-forward.*kube-prom.*alertmanager" 2>/dev/null || true

echo "[*] Deleting test pods..."
kubectl delete namespace test-aiops --ignore-not-found 2>/dev/null || true

echo "[*] Uninstalling kube-prometheus-stack..."
helm uninstall kube-prom -n monitoring 2>/dev/null || true
kubectl delete namespace monitoring --ignore-not-found 2>/dev/null || true

echo "[*] Done. Minikube still running — stop with: minikube stop"
