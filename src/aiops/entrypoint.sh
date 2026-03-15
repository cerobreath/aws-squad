#!/bin/bash
set -e

# Generate kubeconfig for EKS if CLUSTER_NAME is set
if [ -n "$CLUSTER_NAME" ] && [ -n "$AWS_REGION" ]; then
  echo "Generating kubeconfig for cluster $CLUSTER_NAME in $AWS_REGION..."
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
  echo "Kubeconfig ready"
fi

exec uvicorn aiops.web:app --host 0.0.0.0 --port 8000
