variable "project" {
  description = "GCP project ID"
  type        = string
  default     = "my-gcp-project"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "db_instance_name" {
  description = "Cloud SQL instance name (from infrastructure module)"
  type        = string
  default     = "keycloak-prod-db"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "keycloak"
}

variable "keycloak_google_service_account_name" {
  description = "Full service account resource name"
  type        = string
  default     = "projects/my-gcp-project/serviceAccounts/keycloak-prod-sa@my-gcp-project.iam.gserviceaccount.com"
}

variable "keycloak_google_service_account_email" {
  description = "Service account email"
  type        = string
  default     = "keycloak-prod-sa@my-gcp-project.iam.gserviceaccount.com"
}

variable "db_read_users" {
  description = "Users with read-only access to the database"
  type        = set(string)
  default     = ["readonly@example.com", "analyst@example.com"]
}

variable "db_write_users" {
  description = "Users with read-write access to the database"
  type        = set(string)
  default     = ["admin@example.com"]
}

variable "keycloak_image" {
  description = "Keycloak container image"
  type        = string
  default     = "us-central1-docker.pkg.dev/my-gcp-project/keycloak/keycloak:26.4"
}

variable "keycloak_crds_version" {
  description = "Version of Keycloak Operator CRDs"
  type        = string
  default     = "26.4.1"
}

variable "keycloak_operator_version" {
  description = "Version of Keycloak Operator"
  type        = string
  default     = "26.4.1"
}

variable "managed_certificate_host" {
  description = "Domain name for SSL certificate"
  type        = string
  default     = "auth.example.com"
}
