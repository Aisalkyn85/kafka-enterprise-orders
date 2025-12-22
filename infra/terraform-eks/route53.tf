# DNS record for the webapp

data "aws_route53_zone" "main" {
  name         = var.domain_zone
  private_zone = false
}

locals {
  alb_zone_ids = {
    "us-east-1" = "Z35SXDOTRQ7X7K"
    "us-east-2" = "Z3AADJGX6KTTL2"
    "us-west-1" = "Z368ELLRRE2KJ0"
    "us-west-2" = "Z1H1FL5HABSF5"
  }
}

# Wait for the ingress to get an ALB hostname (ALB takes ~60-90s to provision)
resource "time_sleep" "wait_for_alb" {
  depends_on      = [kubernetes_ingress_v1.webapp]
  create_duration = "90s"
}

# Read the ingress after ALB is provisioned
data "kubernetes_ingress_v1" "webapp" {
  metadata {
    name      = kubernetes_ingress_v1.webapp.metadata[0].name
    namespace = "default"
  }
  depends_on = [time_sleep.wait_for_alb]
}

resource "aws_route53_record" "webapp" {
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = var.app_domain
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = data.kubernetes_ingress_v1.webapp.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = local.alb_zone_ids[var.aws_region]
    evaluate_target_health = true
  }
  depends_on = [data.kubernetes_ingress_v1.webapp]
}

output "webapp_url" {
  value = "https://${var.app_domain}"
}

output "alb_hostname" {
  value = data.kubernetes_ingress_v1.webapp.status[0].load_balancer[0].ingress[0].hostname
}
