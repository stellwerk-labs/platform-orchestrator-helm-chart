locals {
  runner_id = "kubernetes-${var.cluster_name}"
}

data "external" "cluster_credentials" {
  program = ["bash", "-c", <<-EOF
    echo '{
      "certificate_authority_data": "'$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' --raw)'",
      "client_certificate_data": "'$(kubectl config view --minify -o jsonpath='{.users[0].user.client-certificate-data}' --raw)'",
      "client_key_data": "'$(kubectl config view --minify -o jsonpath='{.users[0].user.client-key-data}' --raw)'"
    }'
  EOF
  ]
}

resource "kubernetes_namespace" "runner" {
  metadata {
    name = var.runner_namespace
  }
}

resource "kubernetes_service_account" "runner" {
  metadata {
    name      = var.runner_service_account
    namespace = kubernetes_namespace.runner.metadata[0].name
  }
}

resource "kubernetes_role" "runner_orchestrator_access" {
  metadata {
    name      = "platform-orchestrator-runner-orchestrator-access"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["create", "get", "list", "watch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding" "runner_orchestrator_access" {
  metadata {
    name      = "platform-orchestrator-runner-orchestrator-access"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.runner_orchestrator_access.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.runner.metadata[0].name
    namespace = kubernetes_namespace.runner.metadata[0].name
  }
}

resource "platform-orchestrator_kubernetes_runner" "runner" {
  id = local.runner_id

  runner_configuration = {
    cluster = {
      cluster_data = {
        certificate_authority_data = data.external.cluster_credentials.result.certificate_authority_data
        server                     = var.cluster_server
      }
      auth = {
        client_certificate_data = data.external.cluster_credentials.result.client_certificate_data
        client_key_data         = data.external.cluster_credentials.result.client_key_data
      }
    }
    job = {
      namespace       = kubernetes_namespace.runner.metadata[0].name
      service_account = kubernetes_service_account.runner.metadata[0].name
      pod_template = jsonencode({
        spec = {
          containers = [
            {
              name  = "main"
              env = [
                {
                  name = "PLATFORM_ORCHESTRATOR_API_PREFIX"
                  value = "http://platform-orchestrator-data-plane.platform-orchestrator.svc.cluster.local:8080"
                }
              ]
            }
          ]
        }
      })
    }
  }

  state_storage_configuration = {
    type = "kubernetes"
    kubernetes_configuration = {
      namespace = var.runner_namespace
    }
  }
}

resource "platform-orchestrator_runner_rule" "default" {
  runner_id = platform-orchestrator_kubernetes_runner.runner.id
}
