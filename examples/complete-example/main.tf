# ==============================================================================
# INFRASTRUCTURE MODULE
# ==============================================================================
# Deploy this first to create the foundational GCP infrastructure including
# VPC, Cloud SQL database, GKE cluster, and GCP service accounts.
#
# Run: terraform apply -target=module.keycloak_infrastructure
# ==============================================================================

module "keycloak_infrastructure" {
  source = "github.com/pcjsam/terraform-google-keycloak//modules/infrastructure"

  # Project Configuration
  project = var.project
  region  = var.region
  number  = var.number

  # Keycloak Configuration
  keycloak_image_project_id = var.keycloak_image_project_id
}

# ==============================================================================
# APPLICATION MODULE
# ==============================================================================
# Deploy this after the infrastructure module is ready. This will deploy
# Keycloak application resources including Kubernetes configurations,
# database grants, and ingress setup.
#
# Uncomment the provider configurations below and the module block, then run:
# terraform apply
# ==============================================================================

module "keycloak_application" {
  source = "github.com/pcjsam/terraform-google-keycloak//modules/application"

  # Project Configuration
  project = var.project
  region  = var.region

  # Infrastructure outputs
  db_instance_name                      = module.keycloak_infrastructure.cloud_sql_instance_name
  keycloak_google_service_account_name  = "projects/${var.project}/serviceAccounts/${module.keycloak_infrastructure.keycloak_gcp_service_account_email}"
  keycloak_google_service_account_email = module.keycloak_infrastructure.keycloak_gcp_service_account_email

  # Keycloak Configuration
  keycloak_image            = var.keycloak_image
  keycloak_crds_version     = var.keycloak_crds_version
  keycloak_operator_version = var.keycloak_operator_version
  managed_certificate_host  = var.managed_certificate_host

  # Dependencies: Ensure infrastructure is deployed before application
  depends_on = [module.keycloak_infrastructure]
}
