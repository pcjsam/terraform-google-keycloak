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
  default     = "keycloak-instance"
}

variable "keycloak_google_service_account_name" {
  description = "Full service account resource name"
  type        = string
  default     = "projects/my-gcp-project/serviceAccounts/keycloak-gsa@my-gcp-project.iam.gserviceaccount.com"
}

variable "keycloak_google_service_account_email" {
  description = "Service account email"
  type        = string
  default     = "keycloak-gsa@my-gcp-project.iam.gserviceaccount.com"
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
  default     = "keycloak.example.com"
}
