# ArgoCD setup

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
  lifecycle {
    ignore_changes = all
  }
  depends_on = [module.eks]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "5.51.6"

  timeout = 600  # 10 minutes timeout

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }

  depends_on = [module.eks, helm_release.alb_controller, kubernetes_namespace.argocd]
}

# GHCR pull secret
resource "kubernetes_secret" "ghcr" {
  metadata {
    name      = "ghcr"
    namespace = "default"
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.ghcr_username
          password = var.ghcr_pat
          auth     = base64encode("${var.ghcr_username}:${var.ghcr_pat}")
        }
      }
    })
  }
  lifecycle {
    ignore_changes = all
  }
  depends_on = [module.eks]
}

# Webapp deployment via ArgoCD (without ingress - we create it separately)
resource "kubectl_manifest" "webapp_application" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: webapp
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: https://github.com/Aisalkyn85/kafka-enterprise-orders.git
        targetRevision: main
        path: k8s/charts/webapp
        helm:
          values: |
            frontendImage: ghcr.io/aisalkyn85/kafka-enterprise-orders/web-frontend:latest
            backendImage: ghcr.io/aisalkyn85/kafka-enterprise-orders/web-backend:latest
            backendPort: 8000
            replicaCount: 1
            ghcr:
              enabled: false
            ingress:
              enabled: false
            couchbase:
              host: ${var.couchbase_host}
              bucket: ${var.couchbase_bucket}
              username: ${var.couchbase_username}
              password: ${var.couchbase_password}
      destination:
        server: https://kubernetes.default.svc
        namespace: default
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
  YAML
  depends_on = [helm_release.argocd, kubernetes_secret.ghcr]
}

# Wait for ArgoCD to sync and create the webapp service
resource "time_sleep" "wait_for_argocd_sync" {
  depends_on      = [kubectl_manifest.webapp_application]
  create_duration = "90s"
}

# Create Ingress directly via Terraform (supports both ALB and domain access with HTTPS)
resource "kubernetes_ingress_v1" "webapp" {
  metadata {
    name      = "webapp"
    namespace = "default"
    annotations = {
      "kubernetes.io/ingress.class"                = "alb"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
      "alb.ingress.kubernetes.io/certificate-arn"  = var.certificate_arn
      "alb.ingress.kubernetes.io/healthcheck-path" = "/"
    }
  }

  spec {
    # Default rule - allows direct ALB access (no host restriction)
    rule {
      http {
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = "webapp"
              port {
                number = 8000
              }
            }
          }
        }
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "webapp"
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    # Host-specific rule for domain access
    rule {
      host = var.app_domain
      http {
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = "webapp"
              port {
                number = 8000
              }
            }
          }
        }
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "webapp"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [time_sleep.wait_for_argocd_sync, helm_release.alb_controller]

  lifecycle {
    ignore_changes = [metadata[0].annotations["kubectl.kubernetes.io/last-applied-configuration"]]
  }
}
