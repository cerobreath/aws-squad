output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority" {
  description = "EKS cluster CA certificate (base64)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "EKS-managed cluster security group ID"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "aws_lb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller (IRSA)"
  value       = aws_iam_role.aws_lb_controller.arn
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN for the domain"
  value       = aws_acm_certificate_validation.main.certificate_arn
}

output "ecr_frontend_url" {
  description = "ECR repository URL for frontend"
  value       = local.ecr_urls["frontend"]
}

output "ecr_productcatalogservice_url" {
  description = "ECR repository URL for productcatalogservice"
  value       = local.ecr_urls["productcatalogservice"]
}

output "ecr_currencyservice_url" {
  description = "ECR repository URL for currencyservice"
  value       = local.ecr_urls["currencyservice"]
}

output "amp_workspace_endpoint" {
  description = "Amazon Managed Prometheus remote write endpoint"
  value       = aws_prometheus_workspace.main.prometheus_endpoint
}

output "grafana_workspace_endpoint" {
  description = "AWS Managed Grafana workspace URL"
  value       = aws_grafana_workspace.main.endpoint
}

output "otel_collector_role_arn" {
  description = "IAM role ARN for OTEL Collector (IRSA)"
  value       = aws_iam_role.otel_collector.arn
}

output "grafana_api_token" {
  description = "Grafana service account API token for CI/CD automation"
  value       = aws_grafana_workspace_service_account_token.ci_cd.key
  sensitive   = true
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "origin_acm_certificate_arn" {
  description = "ACM certificate ARN for origin subdomains (used by ALB)"
  value       = aws_acm_certificate_validation.origin.certificate_arn
}

output "elasticache_endpoint" {
  description = "ElastiCache Serverless endpoint for cart database"
  value       = aws_elasticache_serverless_cache.main.endpoint[0].address
}
