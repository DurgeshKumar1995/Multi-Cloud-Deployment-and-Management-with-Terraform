locals {
  dns_targets = merge(
    var.enable_aws ? {
      aws = {
        record_type = "CNAME"
        value       = module.aws[0].endpoint_hostname
      }
    } : {},
    var.enable_azure ? {
      azure = {
        record_type = "A"
        value       = module.azure[0].public_ip
      }
    } : {},
    var.enable_gcp ? {
      gcp = {
        record_type = "A"
        value       = module.gcp[0].public_ip
      }
    } : {}
  )
}

resource "aws_route53_record" "provider" {
  for_each = var.enable_dns ? local.dns_targets : {}

  zone_id = var.hosted_zone_id
  name    = "${each.key}.${var.domain_name}"
  type    = each.value.record_type
  ttl     = 60
  records = [each.value.value]
}

resource "aws_route53_health_check" "provider" {
  for_each = var.enable_dns ? local.dns_targets : {}

  fqdn              = aws_route53_record.provider[each.key].fqdn
  port              = 80
  type              = "HTTP"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30

  tags = merge(local.common_tags, {
    Name  = "${var.name_prefix}-${each.key}"
    Cloud = each.key
  })
}

resource "aws_route53_record" "application" {
  for_each = var.enable_dns ? local.dns_targets : {}

  zone_id         = var.hosted_zone_id
  name            = var.application_hostname
  type            = "CNAME"
  ttl             = 60
  records         = [aws_route53_record.provider[each.key].fqdn]
  set_identifier  = each.key
  health_check_id = aws_route53_health_check.provider[each.key].id

  weighted_routing_policy {
    weight = 100
  }
}

