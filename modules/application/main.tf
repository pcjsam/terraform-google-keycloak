/* 
** ******************************************************
** Database - Writers and readers
** ******************************************************
*/

resource "postgresql_grant" "postgres_grants" {
  for_each    = setunion(var.db_read_users, var.db_write_users)
  database    = var.db_name
  object_type = "database"
  privileges  = ["CONNECT"]
  role        = each.value
}

resource "postgresql_grant_role" "read" {
  for_each   = setunion(var.db_read_users, var.db_write_users)
  role       = each.value
  grant_role = "pg_read_all_data"
}

resource "postgresql_grant_role" "write" {
  for_each   = var.db_write_users
  role       = each.value
  grant_role = "pg_write_all_data"
}

/* 
** ******************************************************
** Keycloak - GCP Service Account
** ******************************************************
*/

resource "postgresql_grant" "keycloak_database_grant" {
  database    = var.db_name
  object_type = "database"
  privileges  = ["CONNECT"]
  role        = trimsuffix(var.keycloak_google_service_account_email, ".gserviceaccount.com")
}

resource "postgresql_grant" "keycloak_schema_grant" {
  database    = var.db_name
  object_type = "schema"
  schema      = "public"
  privileges  = ["CREATE", "USAGE"]
  role        = trimsuffix(var.keycloak_google_service_account_email, ".gserviceaccount.com")
}

resource "postgresql_grant_role" "keycloak_table_grant" {
  role       = trimsuffix(var.keycloak_google_service_account_email, ".gserviceaccount.com")
  grant_role = "pg_write_all_data"
}

/*
** ******************************************************
** Keycloak - Keycloak Namespace
** ******************************************************
*/

resource "kubernetes_namespace_v1" "keycloak_namespace" {
  metadata {
    name = var.keycloak_namespace_name
  }

  timeouts {
    delete = "2m"
  }
}

# This resource handles stuck namespace deletion in GKE Autopilot
# It runs AFTER all namespace resources are destroyed but BEFORE the namespace itself
# This is critical because GKE Autopilot often has broken metrics-server APIService
# which causes namespace deletions to hang indefinitely
resource "terraform_data" "namespace_finalizer_cleanup" {
  # Use the variable directly instead of referencing the namespace resource
  # This prevents creating a dependency on the namespace resource itself
  input = var.keycloak_namespace_name

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e  # Exit on error to fail fast if something goes wrong
      NAMESPACE="${self.input}"

      echo "========================================="
      echo "Namespace Finalizer Cleanup Starting"
      echo "Namespace: $NAMESPACE"
      echo "========================================="

      # Check if namespace exists
      if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        echo "✓ Namespace does not exist - nothing to clean up"
        exit 0
      fi

      echo "⏳ Namespace exists. Waiting for Terraform to initiate namespace deletion..."

      # Wait for namespace to enter Terminating state (up to 60 seconds)
      NAMESPACE_TERMINATING=false
      for i in {1..60}; do
        PHASE=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

        if [ "$PHASE" = "NotFound" ] || [ -z "$PHASE" ]; then
          echo "✓ Namespace was deleted successfully"
          exit 0
        fi

        if [ "$PHASE" = "Terminating" ]; then
          echo "✓ Namespace entered Terminating state"
          NAMESPACE_TERMINATING=true
          break
        fi

        if [ $i -eq 60 ]; then
          echo "⚠ WARNING: Namespace did not enter Terminating state after 60s"
          echo "⚠ Current phase: $PHASE"
          echo "⚠ This is unusual but proceeding anyway..."
        fi

        sleep 1
      done

      # Wait 10 seconds to give Kubernetes a chance to complete deletion naturally
      echo "⏳ Waiting 10 seconds for natural namespace deletion..."
      sleep 10

      # Check if namespace still exists
      if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        echo "✓ Namespace deleted successfully without intervention"
        exit 0
      fi

      echo "⚠ Namespace still exists after 10s - likely stuck due to finalizers"
      echo "🔧 Removing namespace finalizers to force deletion..."

      # Check if jq is available
      if ! command -v jq &>/dev/null; then
        echo "✗ ERROR: jq is not installed and is required for this operation"
        echo "✗ Please install jq: https://stedolan.github.io/jq/download/"
        exit 1
      fi

      # Remove finalizers using the /finalize API endpoint
      # This is the same command that works manually
      if kubectl get namespace "$NAMESPACE" -o json | \
         jq '.spec.finalizers = []' | \
         kubectl replace --raw /api/v1/namespaces/$NAMESPACE/finalize -f - &>/dev/null; then
        echo "✓ Finalizers removed successfully"
      else
        echo "✗ Failed to remove finalizers via /finalize endpoint"
        exit 1
      fi

      # Wait for namespace to be deleted (up to 30 seconds)
      echo "⏳ Waiting for namespace deletion to complete..."
      for i in {1..30}; do
        if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
          echo "✓ SUCCESS: Namespace deleted successfully"
          echo "========================================="
          exit 0
        fi
        sleep 1
      done

      # If we get here, the namespace still exists after finalizer removal
      echo "✗ ERROR: Namespace still exists after 30s despite finalizer removal"
      kubectl get namespace "$NAMESPACE" -o yaml 2>/dev/null || true
      exit 1
    EOT
  }

  # CRITICAL: This resource depends on ALL resources that live in the namespace
  # During destroy, Terraform destroys in reverse dependency order:
  # 1. First: All these resources below get destroyed
  # 2. Then: This terraform_data resource gets destroyed (destroy provisioner runs)
  # 3. Finally: The namespace resource gets destroyed
  depends_on = [
    kubernetes_service_account_v1.keycloak_ksa,
    google_service_account_iam_member.keycloak_ksa_iam,
    kubectl_manifest.keycloak_operator,
    terraform_data.wait_for_crds,
    kubernetes_manifest.keycloak_bootstrap_admin_secret,
    kubernetes_manifest.keycloak_db_secret,
    kubectl_manifest.keycloak_instance,
    kubernetes_manifest.frontend_config,
    kubernetes_manifest.managed_certificate,
    kubernetes_manifest.backend_config,
    kubernetes_ingress_v1.ingress,
  ]
}

/* 
** ******************************************************
** Keycloak - Kubernetes Service Account
** ******************************************************
*/

resource "kubernetes_service_account_v1" "keycloak_ksa" {
  metadata {
    name      = var.keycloak_k8s_service_account_name
    namespace = kubernetes_namespace_v1.keycloak_namespace.metadata[0].name
    # This annotation links the KSA to the GSA for Workload Identity
    annotations = {
      "iam.gke.io/gcp-service-account" = var.keycloak_google_service_account_email
    }
  }
}

resource "google_service_account_iam_member" "keycloak_ksa_iam" {
  service_account_id = var.keycloak_google_service_account_name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project}.svc.id.goog[${kubernetes_namespace_v1.keycloak_namespace.metadata[0].name}/${kubernetes_service_account_v1.keycloak_ksa.metadata[0].name}]"
}

/*
** ******************************************************
** Keycloak - CRDs Installation
** ******************************************************
*/

data "http" "keycloak_crd" {
  url = "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${var.keycloak_crds_version}/kubernetes/keycloaks.k8s.keycloak.org-v1.yml"
}

resource "kubectl_manifest" "keycloak_crd" {
  yaml_body = data.http.keycloak_crd.response_body

  wait_for_rollout = false
}

data "http" "keycloak_realm_import_crd" {
  url = "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${var.keycloak_crds_version}/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml"
}

resource "kubectl_manifest" "keycloak_realm_import_crd" {
  yaml_body = data.http.keycloak_realm_import_crd.response_body

  wait_for_rollout = false
}

# CRDs Readiness Check
resource "terraform_data" "wait_for_crds" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Keycloak CRDs to be established..."

      # Wait for keycloaks.k8s.keycloak.org CRD
      echo "Checking keycloaks.k8s.keycloak.org CRD..."
      if kubectl wait --for=condition=established --timeout=120s crd/keycloaks.k8s.keycloak.org 2>/dev/null; then
        echo "✓ keycloaks.k8s.keycloak.org CRD is established"
      else
        echo "✗ ERROR: keycloaks.k8s.keycloak.org CRD failed to establish"
        exit 1
      fi

      # Wait for keycloakrealmimports.k8s.keycloak.org CRD
      echo "Checking keycloakrealmimports.k8s.keycloak.org CRD..."
      if kubectl wait --for=condition=established --timeout=120s crd/keycloakrealmimports.k8s.keycloak.org 2>/dev/null; then
        echo "✓ keycloakrealmimports.k8s.keycloak.org CRD is established"
      else
        echo "✗ ERROR: keycloakrealmimports.k8s.keycloak.org CRD failed to establish"
        exit 1
      fi

      echo "✓ All Keycloak CRDs are ready"
    EOT
  }

  depends_on = [
    kubectl_manifest.keycloak_crd,
    kubectl_manifest.keycloak_realm_import_crd,
  ]
}

/*
** ******************************************************
** Keycloak - Operator Deployment
** ******************************************************
*/

data "http" "keycloak_operator" {
  url = "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${var.keycloak_operator_version}/kubernetes/kubernetes.yml"
}

resource "kubectl_manifest" "keycloak_operator" {
  yaml_body = data.http.keycloak_operator.response_body

  override_namespace = kubernetes_namespace_v1.keycloak_namespace.metadata[0].name

  wait_for_rollout = true

  depends_on = [
    terraform_data.wait_for_crds,
  ]
}

/*
** ******************************************************
** Keycloak - Bootstrap Admin Secret
** ******************************************************
*/

resource "kubernetes_manifest" "keycloak_bootstrap_admin_secret" {
  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = var.keycloak_bootstrap_admin_secret_name
      namespace = kubernetes_namespace_v1.keycloak_namespace.metadata[0].name
    }
    type = "Opaque"
    data = {
      username = base64encode("admin")
      password = base64encode("admin")
    }
  }
}

/*
** ******************************************************
** Keycloak - Database Secret
** ******************************************************
*/

resource "kubernetes_manifest" "keycloak_db_secret" {
  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = var.keycloak_db_secret_name
      namespace = kubernetes_namespace_v1.keycloak_namespace.metadata[0].name
    }
    type = "Opaque"
    data = {
      username = base64encode(trimsuffix(var.keycloak_google_service_account_email, ".gserviceaccount.com"))
      # Dummy password, will not be used thanks to cloud sql auth proxy
      password = base64encode("dummy-password")
    }
  }
}

/*
** ******************************************************
** Keycloak - Instance
** ******************************************************
*/

resource "kubectl_manifest" "keycloak_instance" {
  yaml_body = yamlencode({
    apiVersion = "k8s.keycloak.org/v2alpha1"
    kind       = "Keycloak"
    metadata = {
      name      = "keycloak"
      namespace = kubernetes_namespace_v1.keycloak_namespace.metadata[0].name
    }
    spec = {
      instances = 1
      image     = var.keycloak_image
      # This is the secret that will be used to bootstrap the admin user
      bootstrapAdmin = {
        user = {
          secret = var.keycloak_bootstrap_admin_secret_name
        }
      }
      db = {
        vendor   = "postgres"
        host     = "127.0.0.1"
        port     = 5432
        database = var.db_name
        usernameSecret = {
          name = var.keycloak_db_secret_name
          key  = "username"
        }
        passwordSecret = {
          name = var.keycloak_db_secret_name
          key  = "password"
        }
      }
      # Hostname false to use an Ingress object
      hostname = {
        strict = false
      }
      # HTTP true to use an Ingress object
      http = {
        httpEnabled = true
        httpPort    = 8080
        annotations = {
          "beta.cloud.google.com/backend-config" = "{\"default\": \"${var.backend_config_name}\"}"
        }
      }
      # Proxy headers to use an Ingress object
      proxy = {
        headers = "xforwarded"
      }
      additionalOptions = [
        {
          name  = "health-enabled"
          value = "true"
        },
        {
          name  = "metrics-enabled"
          value = "true"
        }
      ]
      unsupported = {
        podTemplate = {
          spec = {
            serviceAccountName = kubernetes_service_account_v1.keycloak_ksa.metadata[0].name
            initContainers = [
              {
                name          = "cloud-sql-proxy"
                restartPolicy = "Always"
                image         = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.14.1"
                args = [
                  "${var.project}:${var.region}:${var.db_instance_name}",
                  "--private-ip",
                  "--auto-iam-authn",
                  "--structured-logs",
                  "--port=5432"
                ]
                securityContext = {
                  runAsNonRoot = true
                }
                resources = {
                  requests = {
                    memory = "2Gi"
                    cpu    = "1000m"
                  }
                }
              }
            ]
          }
        }
      }
    }
  })

  depends_on = [
    kubectl_manifest.keycloak_operator,
    kubernetes_manifest.keycloak_bootstrap_admin_secret,
    kubernetes_manifest.keycloak_db_secret,
  ]
}

/* 
** ******************************************************
** Keycloak - Frontend Configuration
** ******************************************************
*/

resource "kubernetes_manifest" "frontend_config" {
  manifest = {
    apiVersion = "networking.gke.io/v1beta1"
    kind       = "FrontendConfig"
    metadata = {
      name      = var.frontend_config_name
      namespace = kubernetes_namespace_v1.keycloak_namespace.metadata[0].name
    }
    spec = {
      redirectToHttps = {
        enabled = true
      }
      sslPolicy = var.ssl_policy_name
    }
  }

  depends_on = [kubectl_manifest.keycloak_instance]
}

/*
** ******************************************************
** Keycloak - Managed Certificate
** ******************************************************
*/

resource "kubernetes_manifest" "managed_certificate" {
  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = var.managed_certificate_name
      namespace = kubernetes_namespace_v1.keycloak_namespace.metadata[0].name
    }
    spec = {
      domains = [var.managed_certificate_host]
    }
  }

  depends_on = [kubectl_manifest.keycloak_instance]
}

/*
** ******************************************************
** Keycloak - Backend Config
** ******************************************************
*/

resource "kubernetes_manifest" "backend_config" {
  manifest = {
    apiVersion = "cloud.google.com/v1"
    kind       = "BackendConfig"
    metadata = {
      name      = var.backend_config_name
      namespace = kubernetes_namespace_v1.keycloak_namespace.metadata[0].name
    }
    spec = {
      healthCheck = {
        requestPath = "/health/ready"
        port        = 9000
        type        = "HTTP"
      }
    }
  }

  depends_on = [kubectl_manifest.keycloak_instance]
}

/* 
** ******************************************************
** Keycloak - Ingress
** ******************************************************
*/

resource "kubernetes_ingress_v1" "ingress" {
  metadata {
    name      = var.ingress_name
    namespace = kubernetes_namespace_v1.keycloak_namespace.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = var.public_ip_address_name
      "networking.gke.io/v1beta1.FrontendConfig"    = var.frontend_config_name
      "networking.gke.io/managed-certificates"      = var.managed_certificate_name
    }
  }

  spec {
    rule {
      host = var.managed_certificate_host
      http {
        path {
          path = "/*"
          backend {
            service {
              name = "keycloak-service"
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.backend_config, kubernetes_manifest.managed_certificate]
}
