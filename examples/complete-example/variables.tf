# ==============================================================================
# PROJECT CONFIGURATION
# ==============================================================================

variable "project" {
  description = "GCP project ID"
  type        = string
  default     = "my-gcp-project"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "number" {
  description = "GCP project number"
  type        = string
  default     = "123456789012"
}

# ==============================================================================
# INFRASTRUCTURE MODULE VARIABLES
# ==============================================================================

variable "keycloak_image_project_id" {
  description = "GCP project ID where Keycloak container image is hosted"
  type        = string
  default     = "my-gcp-project"
}

# ==============================================================================
# APPLICATION MODULE VARIABLES
# ==============================================================================

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
