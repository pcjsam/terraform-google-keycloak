module "keycloak_application" {
  source = "github.com/pcjsam/terraform-google-keycloak//modules/application"

  # Project Configuration
  project = var.project
  region  = var.region

  # Infrastructure outputs
  db_instance_name                      = var.db_instance_name
  keycloak_google_service_account_name  = var.keycloak_google_service_account_name
  keycloak_google_service_account_email = var.keycloak_google_service_account_email

  # Keycloak Configuration
  keycloak_image            = var.keycloak_image
  keycloak_crds_version     = var.keycloak_crds_version
  keycloak_operator_version = var.keycloak_operator_version
  managed_certificate_host  = var.managed_certificate_host
}
