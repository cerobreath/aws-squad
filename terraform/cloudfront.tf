# CloudFront distribution in front of ALB for static asset caching

locals {
  is_production    = terraform.workspace == "production"
  cloudfront_domain = local.is_production ? var.domain_name : "staging.${var.domain_name}"
  origin_domain     = local.is_production ? "origin.${var.domain_name}" : "origin-staging.${var.domain_name}"
}

# ACM certificate in us-east-1 (required by CloudFront)
resource "aws_acm_certificate" "cloudfront" {
  provider    = aws.us_east_1
  domain_name = local.cloudfront_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# ACM validation CNAMEs are identical per domain regardless of certificate or region,
# so we reuse the DNS records created for the main cert.
resource "aws_acm_certificate_validation" "cloudfront" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for record in cloudflare_record.acm_validation : record.hostname]
}

# Managed cache policies
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "main" {
  enabled         = true
  is_ipv6_enabled = true
  aliases         = [local.cloudfront_domain]
  price_class     = var.cloudfront_price_class
  comment         = "${var.project_name} ${terraform.workspace}"

  origin {
    domain_name = local.origin_domain
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default behavior — dynamic content, no caching
  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # Static assets — cached for 24h
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  depends_on = [aws_acm_certificate_validation.cloudfront]
}

# One-time cleanup: delete old DNS record created by ExternalDNS for the main domain.
# The provisioner runs only on resource creation, so subsequent applies are unaffected.
resource "terraform_data" "cleanup_old_cloudfront_dns" {
  provisioner "local-exec" {
    command = <<-EOT
      RECORDS=$(curl -s "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$DOMAIN" \
        -H "Authorization: Bearer $CF_TOKEN" | jq -r '.result[].id // empty')
      for id in $RECORDS; do
        echo "Deleting old DNS record $id for $DOMAIN"
        curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$id" \
          -H "Authorization: Bearer $CF_TOKEN"
      done
    EOT
    environment = {
      CF_TOKEN = var.cloudflare_api_token
      ZONE_ID  = var.cloudflare_zone_id
      DOMAIN   = local.cloudfront_domain
    }
  }
}

# DNS: point main domain to CloudFront
resource "cloudflare_record" "cloudfront" {
  depends_on = [terraform_data.cleanup_old_cloudfront_dns]
  zone_id    = var.cloudflare_zone_id
  name       = local.cloudfront_domain
  type       = "CNAME"
  content    = aws_cloudfront_distribution.main.domain_name
  proxied    = false
  ttl        = 300
}
