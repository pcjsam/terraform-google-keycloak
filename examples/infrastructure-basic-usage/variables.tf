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

variable "keycloak_image_project_id" {
  description = "GCP project ID where Keycloak container image is hosted"
  type        = string
  default     = "my-gcp-project"
}
