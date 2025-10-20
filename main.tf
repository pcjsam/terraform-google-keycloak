/* 
** ******************************************************
** Networking - VPC and Subnet
** ******************************************************
*/

resource "google_compute_network" "network" {
  name                    = var.network_name
  auto_create_subnetworks = var.network_auto_create_subnetworks
}

resource "google_compute_subnetwork" "subnetwork" {
  name                     = var.subnetwork_name
  network                  = google_compute_network.network.id
  ip_cidr_range            = var.subnetwork_ip_cidr_range
  region                   = var.project
  private_ip_google_access = var.subnetwork_private_ip_google_access
}

/* 
** ******************************************************
** Database VPC Connection
** ******************************************************
*/

resource "google_compute_global_address" "private_ip_address" {
  name          = var.private_ip_address_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
  deletion_policy         = ""
}

/* 
** ******************************************************
** Database Instance
** ******************************************************
*/

resource "google_sql_database_instance" "postgresql_instance" {
  name                = var.db_instance_name
  project             = var.project
  region              = var.region
  database_version    = var.db_version
  deletion_protection = var.db_deletion_protection

  settings {
    tier                  = var.db_tier
    edition               = var.db_edition
    activation_policy     = var.db_activation_policy
    availability_type     = var.db_availability_type
    connector_enforcement = var.db_connector_enforcement
    disk_autoresize       = var.db_disk_autoresize
    disk_type             = var.db_disk_type
    pricing_plan          = var.db_pricing_plan

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    insights_config {
      query_insights_enabled  = var.db_query_insights_enabled
      query_plans_per_minute  = var.db_query_plans_per_minute
      query_string_length     = var.db_query_string_length
      record_application_tags = var.db_record_application_tags
      record_client_address   = var.db_record_client_address
    }

    maintenance_window {
      day  = var.db_maintenance_window_day
      hour = var.db_maintenance_window_hour
    }

    backup_configuration {
      enabled                        = var.db_backup_enabled
      start_time                     = var.db_backup_start_time
      point_in_time_recovery_enabled = var.db_point_in_time_recovery_enabled
      transaction_log_retention_days = var.db_transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.db_backup_retention_count
        retention_unit   = var.db_backup_retention_unit
      }
    }

    ip_configuration {
      ipv4_enabled                                  = var.public_ipv4_enabled
      private_network                               = google_compute_network.network.id
      enable_private_path_for_google_cloud_services = var.db_enable_private_path_for_google_cloud_services
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

/* 
** ******************************************************
** Database
** ******************************************************
*/

resource "google_sql_database" "postgresql_db" {
  name      = var.db_name
  project   = var.project
  instance  = google_sql_database_instance.postgresql_instance.name
  charset   = var.db_charset
  collation = var.db_collation

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

/* 
** ******************************************************
** Database - User
** ******************************************************
*/

resource "google_sql_user" "postgresql_user" {
  name     = var.db_user_name
  instance = google_sql_database_instance.postgresql_instance.name
  password = "change_me"

  lifecycle {
    ignore_changes = [password]
  }
}

/* 
** ******************************************************
** Database - Writers and readers
** ******************************************************
*/

resource "google_project_iam_member" "cloud_sql_accessors" {
  for_each = setunion(var.db_read_users, var.db_write_users)
  project  = var.project
  member   = "user:${each.value}"
  role     = "roles/cloudsql.client"
}

resource "google_project_iam_member" "cloud_sql_instance_users" {
  for_each = setunion(var.db_read_users, var.db_write_users)
  project  = var.project
  member   = "user:${each.value}"
  role     = "roles/cloudsql.instanceUser"
}

resource "google_sql_user" "postgresql_users" {
  for_each = setunion(var.db_read_users, var.db_write_users)
  instance = google_sql_database_instance.postgresql_instance.name
  name     = each.value
  type     = "CLOUD_IAM_USER"
}

resource "postgresql_grant" "postgres_grants" {
  for_each    = setunion(var.db_read_users, var.db_write_users)
  database    = var.db_name
  object_type = "database"
  privileges  = ["CONNECT"]
  role        = each.value

  depends_on = [
    google_sql_database_instance.postgresql_instance,
    google_sql_database.postgresql_db,
    google_sql_user.postgresql_user
  ]
}

resource "postgresql_grant_role" "read" {
  for_each   = setunion(var.db_read_users, var.db_write_users)
  role       = each.value
  grant_role = "pg_read_all_data"

  depends_on = [
    google_sql_database_instance.postgresql_instance,
    google_sql_database.postgresql_db,
    google_sql_user.postgresql_user
  ]
}

resource "postgresql_grant_role" "write" {
  for_each   = var.db_write_users
  role       = each.value
  grant_role = "pg_write_all_data"

  depends_on = [
    google_sql_database_instance.postgresql_instance,
    google_sql_database.postgresql_db,
    google_sql_user.postgresql_user
  ]
}

/* 
** ******************************************************
** Keycloak - Cluster
** ******************************************************
*/

# GKE Autopilot uses the Compute Default Service Account for the Kubernetes Cluster
locals {
  keycloak_image_project_roles = [
    "roles/artifactregistry.reader",
  ]
}

resource "google_project_iam_member" "compute_engine_default_service_account_iam_development" {
  for_each = toset(local.keycloak_image_project_roles)
  project  = var.keycloak_image_project_id
  role     = each.key
  member   = "serviceAccount:${var.number}-compute@developer.gserviceaccount.com"
}

resource "google_container_cluster" "keycloak_cluster" {
  name                = var.keycloak_cluster_name
  project             = var.project
  location            = var.region
  deletion_protection = var.keycloak_cluster_deletion_protection
  enable_autopilot    = var.keycloak_cluster_enable_autopilot
  networking_mode     = "VPC_NATIVE"
  logging_service     = "logging.googleapis.com/kubernetes"
  network             = google_compute_network.network.id
  subnetwork          = google_compute_subnetwork.subnetwork.id

  secret_manager_config {
    enabled = true
  }
}

/* 
** ******************************************************
** Keycloak - GCP Service Account
** ******************************************************
*/

resource "google_service_account" "keycloak_gsa" {
  account_id   = var.keycloak_google_service_account_name
  display_name = var.keycloak_google_service_account_display_name
  project      = var.project
}

resource "google_project_iam_member" "keycloak_gsa_iam" {
  for_each = toset(var.keycloak_google_service_account_roles)
  project  = var.project
  role     = each.key
  member   = "serviceAccount:${google_service_account.keycloak_gsa.email}"
}

resource "google_sql_user" "keycloak_iam_user" {
  instance = google_sql_database_instance.postgresql_instance.name
  name     = trimsuffix(google_service_account.keycloak_gsa.email, ".gserviceaccount.com")
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "postgresql_grant" "keycloak_database_grant" {
  count       = var.deploy_k8s_grants ? 1 : 0
  database    = google_sql_database.postgresql_db.name
  object_type = "database"
  privileges  = ["CONNECT"]
  role        = trimsuffix(google_service_account.keycloak_gsa.email, ".gserviceaccount.com")

  depends_on = [
    google_sql_database_instance.postgresql_instance,
    google_sql_database.postgresql_db,
    google_sql_user.postgresql_user
  ]
}

resource "postgresql_grant" "keycloak_schema_grant" {
  count       = var.deploy_k8s_grants ? 1 : 0
  database    = google_sql_database.postgresql_db.name
  object_type = "schema"
  schema      = "public"
  privileges  = ["CREATE", "USAGE"]
  role        = trimsuffix(google_service_account.keycloak_gsa.email, ".gserviceaccount.com")

  depends_on = [
    google_sql_database_instance.postgresql_instance,
    google_sql_database.postgresql_db,
    google_sql_user.postgresql_user
  ]
}

resource "postgresql_grant_role" "keycloak_table_grant" {
  count      = var.deploy_k8s_grants ? 1 : 0
  role       = trimsuffix(google_service_account.keycloak_gsa.email, ".gserviceaccount.com")
  grant_role = "pg_write_all_data"

  depends_on = [
    google_sql_database_instance.postgresql_instance,
    google_sql_database.postgresql_db,
    google_sql_user.postgresql_user
  ]
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

  depends_on = [google_container_cluster.keycloak_cluster]
}

/* 
** ******************************************************
** Keycloak - Kubernetes Service Account
** ******************************************************
*/

resource "kubernetes_service_account_v1" "keycloak_ksa" {
  metadata {
    name      = var.keycloak_k8s_service_account_name
    namespace = kubernetes_namespace_v1.keycloak_namespace.metadata["name"]
    # This annotation links the KSA to the GSA for Workload Identity
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.keycloak_gsa.email
    }
  }

  depends_on = [google_container_cluster.keycloak_cluster]
}

resource "google_service_account_iam_member" "keycloak_ksa_iam" {
  service_account_id = google_service_account.keycloak_gsa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project}.svc.id.goog[${kubernetes_namespace_v1.keycloak_namespace.metadata["name"]}/${kubernetes_service_account_v1.keycloak_ksa.metadata[0].name}]"
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

  depends_on = [google_container_cluster.keycloak_cluster]
}

data "http" "keycloak_realm_import_crd" {
  url = "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${var.keycloak_operator_version}/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml"
}

resource "kubectl_manifest" "keycloak_realm_import_crd" {
  yaml_body = data.http.keycloak_realm_import_crd.response_body

  wait_for_rollout = false

  depends_on = [google_container_cluster.keycloak_cluster]
}

/*
** ******************************************************
** Keycloak - Operator Deployment
** ******************************************************
*/

data "http" "keycloak_operator" {
  url = "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.3.3/kubernetes/kubernetes.yml"
}

resource "kubectl_manifest" "keycloak_operator" {
  yaml_body = data.http.keycloak_operator.response_body

  override_namespace = kubernetes_namespace_v1.keycloak_namespace.metadata[0].name

  wait_for_rollout = true

  depends_on = [
    kubectl_manifest.keycloak_crd,
    kubectl_manifest.keycloak_realm_import_crd,
  ]
}

/*
** ******************************************************
** Keycloak - Bootstrap Admin Secret
** ******************************************************
*/

resource "kubernetes_manifest" "keycloak_bootstrap_admin_secret" {
  count = var.deploy_k8s_resources ? 1 : 0
  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = var.keycloak_bootstrap_admin_secret_name
      namespace = kubernetes_namespace_v1.keycloak_namespace.metadata["name"]
    }
    type = "Opaque"
    stringData = {
      username = "admin"
      password = "admin"
    }
  }

  depends_on = [google_container_cluster.keycloak_cluster]
}

/*
** ******************************************************
** Keycloak - Database Secret
** ******************************************************
*/

resource "kubernetes_manifest" "keycloak_db_secret" {
  count = var.deploy_k8s_resources ? 1 : 0
  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = var.keycloak_db_secret_name
      namespace = kubernetes_namespace_v1.keycloak_namespace.metadata["name"]
    }
    type = "Opaque"
    stringData = {
      username = trimsuffix(google_service_account.keycloak_gsa.email, ".gserviceaccount.com")
      # Dummy password, will not be used thanks to cloud sql auth proxy
      password = "dummy-password"
    }
  }

  depends_on = [google_container_cluster.keycloak_cluster]
}

/*
** ******************************************************
** Keycloak - Instance
** ******************************************************
*/

resource "kubernetes_manifest" "keycloak_instance" {
  count = var.deploy_k8s_resources ? 1 : 0
  manifest = {
    apiVersion = "k8s.keycloak.org/v2alpha1"
    kind       = "Keycloak"
    metadata = {
      name      = "keycloak"
      namespace = kubernetes_namespace_v1.keycloak_namespace.metadata["name"]
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
                  "${var.project}:${var.region}:${google_sql_database_instance.postgresql_instance.name}",
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
  }

  depends_on = [
    kubectl_manifest.keycloak_crd,
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

resource "google_compute_ssl_policy" "ssl_policy" {
  name    = var.ssl_policy_name
  profile = var.ssl_policy_profile
}

resource "kubernetes_manifest" "frontend_config" {
  count = var.deploy_k8s_resources ? 1 : 0
  manifest = {
    apiVersion = "networking.gke.io/v1beta1"
    kind       = "FrontendConfig"
    metadata = {
      name      = var.frontend_config_name
      namespace = kubernetes_namespace_v1.keycloak_namespace.metadata["name"]
    }
    spec = {
      redirectToHttps = {
        enabled = true
      }
      sslPolicy = google_compute_ssl_policy.ssl_policy.name
    }
  }

  depends_on = [kubernetes_manifest.keycloak_instance]
}

/* 
** ******************************************************
** Keycloak - Managed Certificate
** ******************************************************
*/

resource "kubernetes_manifest" "managed_certificate" {
  count = var.deploy_k8s_resources ? 1 : 0
  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = var.managed_certificate_name
      namespace = kubernetes_namespace_v1.keycloak_namespace.metadata["name"]
    }
    spec = {
      domains = [var.managed_certificate_host]
    }
  }

  depends_on = [kubernetes_manifest.keycloak_instance]
}

/* 
** ******************************************************
** Keycloak - Backend Config
** ******************************************************
*/

resource "kubernetes_manifest" "backend_config" {
  count = var.deploy_k8s_resources ? 1 : 0
  manifest = {
    apiVersion = "cloud.google.com/v1"
    kind       = "BackendConfig"
    metadata = {
      name      = var.backend_config_name
      namespace = kubernetes_namespace_v1.keycloak_namespace.metadata["name"]
    }
    spec = {
      healthCheck = {
        requestPath = "/health/ready"
        port        = 9000
        type        = "HTTP"
      }
    }
  }

  depends_on = [kubernetes_manifest.keycloak_instance]
}

/* 
** ******************************************************
** Keycloak - Ingress
** ******************************************************
*/

resource "google_compute_global_address" "public_ip_address" {
  name         = var.public_ip_address_name
  address_type = var.public_ip_address_type
}

resource "kubernetes_ingress_v1" "ingress" {
  count = var.deploy_k8s_resources ? 1 : 0
  metadata {
    name      = var.ingress_name
    namespace = kubernetes_namespace_v1.keycloak_namespace.metadata["name"]
    annotations = {
      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.public_ip_address.name
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
