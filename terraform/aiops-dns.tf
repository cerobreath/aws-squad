# ACM certificate for AIOps (ALB TLS termination)

resource "aws_acm_certificate" "aiops" {
  domain_name       = local.aiops_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_record" "aiops_acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.aiops.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      type    = dvo.resource_record_type
      content = dvo.resource_record_value
    } if dvo.domain_name == local.aiops_domain
  }

  zone_id         = var.cloudflare_zone_id
  name            = each.value.name
  type            = each.value.type
  content         = trimsuffix(each.value.content, ".")
  proxied         = false
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "aiops" {
  certificate_arn         = aws_acm_certificate.aiops.arn
  validation_record_fqdns = [for record in cloudflare_record.aiops_acm_validation : record.hostname]
}

# DNS: point aiops domain to ALB
resource "cloudflare_record" "aiops" {
  zone_id = var.cloudflare_zone_id
  name    = local.aiops_domain
  type    = "CNAME"
  content = aws_lb.aiops.dns_name
  proxied = false
  ttl     = 60
}
