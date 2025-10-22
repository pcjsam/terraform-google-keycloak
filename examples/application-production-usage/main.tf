module "keycloak_application" {
  source = "github.com/pcjsam/terraform-google-keycloak//modules/application"

  # Project Configuration
  project = var.project
  region  = var.region

  # Infrastructure outputs
  db_instance_name                      = var.db_instance_name
  db_name                               = var.db_name
  keycloak_google_service_account_name  = var.keycloak_google_service_account_name
  keycloak_google_service_account_email = var.keycloak_google_service_account_email

  # Database Access
  db_read_users  = var.db_read_users
  db_write_users = var.db_write_users

  # Namespace Configuration
  keycloak_namespace_name = "keycloak-prod"

  # Service Account Configuration
  keycloak_k8s_service_account_name = "keycloak-prod-ksa"

  # Keycloak Configuration
  keycloak_image            = var.keycloak_image
  keycloak_crds_version     = var.keycloak_crds_version
  keycloak_operator_version = var.keycloak_operator_version

  # SSL & Ingress Configuration
  managed_certificate_host = var.managed_certificate_host
  ssl_policy_name          = "keycloak-prod-ssl"
  frontend_config_name     = "keycloak-prod-frontend"
  managed_certificate_name = "keycloak-prod-cert"
  backend_config_name      = "keycloak-prod-backend"
  ingress_name             = "keycloak-prod-ingress"
  public_ip_address_name   = "keycloak-prod-ip"
}
