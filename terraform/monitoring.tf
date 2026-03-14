# -----------------------------------------------------------------------------
# Monitoring — Amazon Managed Prometheus + AWS Managed Grafana + X-Ray
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# --- Amazon Managed Prometheus ---

resource "aws_prometheus_workspace" "main" {
  alias = "${local.cluster_name}-amp"

  tags = {
    Name = "${local.cluster_name}-amp"
  }
}

# --- AWS Managed Grafana ---

resource "aws_iam_role" "grafana" {
  name = "${local.cluster_name}-grafana"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "grafana.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        StringLike = {
          "aws:SourceArn" = "arn:aws:grafana:${var.aws_region}:${data.aws_caller_identity.current.account_id}:/workspaces/*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "grafana_amp_xray" {
  name = "grafana-amp-xray"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:QueryMetrics",
          "aps:GetLabels",
          "aps:GetSeries",
          "aps:GetMetricMetadata",
          "aps:ListWorkspaces",
          "aps:DescribeWorkspace",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:GetTraceSummaries",
          "xray:BatchGetTraces",
          "xray:GetServiceGraph",
          "xray:GetTraceGraph",
          "xray:GetInsightSummaries",
          "xray:GetGroups",
          "xray:GetTimeSeriesServiceStatistics",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_grafana_workspace" "main" {
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn
  data_sources             = ["PROMETHEUS", "XRAY"]
  name                     = "${local.cluster_name}-grafana"

  configuration = jsonencode({
    plugins          = { pluginAdminEnabled = true }
    unifiedAlerting  = { enabled = false }
  })

  tags = {
    Name = "${local.cluster_name}-grafana"
  }
}

# --- Service Account for CI/CD automation ---

resource "aws_grafana_workspace_service_account" "ci_cd" {
  workspace_id = aws_grafana_workspace.main.id
  name         = "ci-cd-automation"
  grafana_role = "ADMIN"
}

resource "aws_grafana_workspace_service_account_token" "ci_cd" {
  workspace_id       = aws_grafana_workspace.main.id
  service_account_id = aws_grafana_workspace_service_account.ci_cd.service_account_id
  name               = "ci-cd-token"
  seconds_to_live    = 2592000  # 30 days (maximum)
}

# --- IRSA for OTEL Collector ---

data "aws_iam_policy_document" "otel_collector_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:demo:opentelemetrycollector"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "otel_collector" {
  name               = "${local.cluster_name}-otel-collector"
  assume_role_policy = data.aws_iam_policy_document.otel_collector_assume_role.json
}

resource "aws_iam_role_policy" "otel_amp_xray" {
  name = "otel-amp-xray"
  role = aws_iam_role.otel_collector.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["aps:RemoteWrite"]
        Resource = aws_prometheus_workspace.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
        ]
        Resource = "*"
      },
    ]
  })
}
