[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

[![Stand With Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/banner2-direct.svg)](https://vshymanskyy.github.io/StandWithUkraine/)

# AWS Infrastructure for Retail Store Sample App

[![Deploy](https://github.com/cerobreath/aws-core/actions/workflows/deploy.yml/badge.svg)](https://github.com/cerobreath/aws-core/actions/workflows/deploy.yml)

This repository contains the AWS platform, deployment pipeline, and Kubernetes configuration used to run the [AWS Containers Retail Store Sample App](https://github.com/aws-containers/retail-store-sample-app) on Amazon EKS.

It does not maintain the full upstream application source. It provisions and operates the infrastructure around that application: networking, cluster, ingress, DNS, certificates, image registry, observability, policy enforcement, and backup workflows.

## What This Repository Manages

- Amazon EKS clusters for `staging` and `production`
- VPC, public/private subnets, NAT, and IAM roles
- Amazon ECR repositories for custom images
- CloudFront, ACM, and DNS records for public access
- Argo CD applications for workload delivery
- AWS Load Balancer Controller and ExternalDNS
- Prometheus/Grafana monitoring stack
- Velero backup storage and IAM integration
- Kyverno guardrails and Sealed Secrets

## Stack

| Layer | Technologies |
|---|---|
| Cloud | AWS EKS, ECR, CloudFront, ACM, Route/DNS integration, S3, KMS |
| Infrastructure as Code | Terraform |
| Delivery | GitHub Actions, OIDC, Argo CD, Helm |
| Kubernetes Add-ons | AWS Load Balancer Controller, ExternalDNS, Sealed Secrets, Velero, Kyverno |
| Observability | kube-prometheus-stack, Grafana, OpenTelemetry |
| Application | `aws-containers/retail-store-sample-app` plus custom UI image |

## Deployment Model

- `staging` branch deploys the staging environment
- `main` branch deploys the production environment
- Terraform provisions the AWS foundation first
- GitHub Actions builds and pushes images to ECR
- Argo CD applies and reconciles Kubernetes applications

## Repository Layout

- `terraform/` — AWS infrastructure definitions
- `k8s/` — Argo CD applications and cluster policies
- `src/ui/` — custom storefront UI image and Helm chart overrides
- `src/aiops/` — operational and diagnostic tooling
- `docs/` — diagrams and environment screenshots

## Upstream Application

Application workloads are based on the official AWS sample:

- Upstream repository: `aws-containers/retail-store-sample-app`
- Upstream URL: <https://github.com/aws-containers/retail-store-sample-app>

## Notes

- Environment-specific Terraform values are stored in `terraform/envs/`
- Public entrypoints, certificates, and DNS are managed from this repository
- Cluster add-ons and platform services are deployed declaratively through Argo CD
