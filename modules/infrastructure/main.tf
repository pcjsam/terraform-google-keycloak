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
  region                   = var.region
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

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Deleting VPC peering before IP address deletion..."

      # Delete the peering first, before the IP address is deleted
      # The peering uses this IP address range, so it must be deleted first
      # Extract network name and project from the network ID (format: projects/{project}/global/networks/{network})
      NETWORK_ID="${self.network}"
      NETWORK_NAME=$(echo "$NETWORK_ID" | sed 's|.*/networks/||')
      PROJECT=$(echo "$NETWORK_ID" | sed 's|projects/||; s|/.*||')

      gcloud compute networks peerings delete servicenetworking-googleapis-com \
        --network="$NETWORK_NAME" \
        --project="$PROJECT" \
        --quiet 2>&1 && echo "✓ VPC peering deleted" || echo "Peering already deleted or doesn't exist"
    EOT
  }
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]

  # ABANDON: Don't try to delete via Service Networking API (it's buggy)
  # We delete the peering manually via Compute API in the network's destroy provisioner
  deletion_policy = "ABANDON"
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
  cluster_roles = [
    "roles/container.defaultNodeServiceAccount",
  ]
}

resource "google_project_iam_member" "compute_engine_default_service_account_iam_keycloak_image_project_roles" {
  for_each = toset(local.keycloak_image_project_roles)
  project  = var.keycloak_image_project_id
  role     = each.key
  member   = "serviceAccount:${var.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "compute_engine_default_service_account_iam_cluster_roles" {
  for_each = toset(local.cluster_roles)
  project  = var.project
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

# Cluster Readiness Check
resource "terraform_data" "wait_for_cluster" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for GKE cluster to be ready..."

      # Wait for cluster to be in RUNNING state
      for i in {1..60}; do
        STATUS=$(gcloud container clusters describe ${google_container_cluster.keycloak_cluster.name} \
          --region ${var.region} \
          --project ${var.project} \
          --format="value(status)" 2>/dev/null || echo "ERROR")

        if [ "$STATUS" = "RUNNING" ]; then
          echo "✓ Cluster is in RUNNING state"

          # Additional check: verify API server is responding
          if gcloud container clusters get-credentials ${google_container_cluster.keycloak_cluster.name} \
            --region ${var.region} \
            --project ${var.project} \
            --quiet 2>/dev/null; then

            # Try to connect to the API server
            if kubectl cluster-info --request-timeout=5s &>/dev/null; then
              echo "✓ Cluster API server is accepting connections"
              exit 0
            else
              echo "⏳ API server not ready yet, waiting... (attempt $i/60)"
            fi
          fi
        else
          echo "⏳ Cluster status: $STATUS, waiting... (attempt $i/60)"
        fi

        sleep 10
      done

      echo "✗ ERROR: Cluster did not become ready within 10 minutes"
      exit 1
    EOT
  }

  depends_on = [google_container_cluster.keycloak_cluster]
}

# Data sources for cluster provider configuration
data "google_container_cluster" "keycloak_cluster" {
  name     = google_container_cluster.keycloak_cluster.name
  location = google_container_cluster.keycloak_cluster.location

  depends_on = [terraform_data.wait_for_cluster]
}

data "google_client_config" "current" {}

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

/* 
** ******************************************************
** Keycloak - Frontend Configuration
** ******************************************************
*/

resource "google_compute_ssl_policy" "ssl_policy" {
  name    = var.ssl_policy_name
  profile = var.ssl_policy_profile
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
