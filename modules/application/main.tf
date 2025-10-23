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
    delete = "10m"
  }

  provisioner "local-exec" {
    when = destroy

    environment = {
      NAMESPACE = self.metadata[0].name
    }

    command = <<-EOF
      nohup bash -c '
        for i in {1..36}; do
          PHASE=$(kubectl get namespace "$NAMESPACE" -o jsonpath="{.status.phase}" 2>/dev/null)

          if [ -z "$PHASE" ]; then
            exit 0
          fi

          if [ "$PHASE" = "Terminating" ]; then
            sleep 30
            if kubectl get namespace "$NAMESPACE" &>/dev/null; then
              kubectl get namespace "$NAMESPACE" -o json | jq ".spec.finalizers = []" | kubectl replace --raw /api/v1/namespaces/$NAMESPACE/finalize -f - || true
            fi
            exit 0
          fi

          sleep 5
        done
      ' > /dev/null 2>&1 &
      disown
    EOF
  }
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

data "kubectl_file_documents" "keycloak_operator_docs" {
  content = data.http.keycloak_operator.response_body
}

resource "kubectl_manifest" "keycloak_operator" {
  for_each = data.kubectl_file_documents.keycloak_operator_docs.manifests

  yaml_body = each.value

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
