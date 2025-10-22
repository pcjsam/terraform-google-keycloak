module "keycloak_infrastructure" {
  source = "github.com/pcjsam/terraform-google-keycloak//modules/infrastructure"

  # Project Configuration
  project = var.project
  region  = var.region
  number  = var.number

  # Network Configuration
  network_name                        = "keycloak-prod-network"
  subnetwork_name                     = "keycloak-prod-subnet"
  subnetwork_ip_cidr_range            = "10.10.0.0/16"
  subnetwork_private_ip_google_access = true

  # Database Configuration
  db_instance_name       = "keycloak-prod-db"
  db_version             = "POSTGRES_17"
  db_deletion_protection = true
  db_tier                = "db-perf-optimized-N-4"
  db_edition             = "ENTERPRISE_PLUS"
  db_availability_type   = "REGIONAL"

  # Database Access
  db_read_users  = var.db_read_users
  db_write_users = var.db_write_users

  # Keycloak Configuration
  keycloak_image_project_id            = var.keycloak_image_project_id
  keycloak_cluster_name                = "keycloak-prod-cluster"
  keycloak_cluster_deletion_protection = true
  keycloak_google_service_account_name = "keycloak-prod-sa"

  # SSL Configuration
  ssl_policy_name    = "keycloak-prod-ssl"
  ssl_policy_profile = "MODERN"
}
