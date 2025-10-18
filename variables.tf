/* 
** ******************************************************
** Project variables
** ******************************************************
*/

variable "project" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP project region"
}

variable "number" {
  type        = string
  description = "GCP project number"
}

/* 
** ******************************************************
** Networking - VPC and Subnet
** ******************************************************
*/

variable "network_name" {
  type        = string
  description = "The name of the VPC network"
  default     = "keycloak-network"
}

variable "network_auto_create_subnetworks" {
  type        = bool
  description = "When set to true, the network is created in auto mode"
  default     = false
}

variable "subnetwork_name" {
  type        = string
  description = "The name of the subnetwork"
  default     = "keycloak-subnetwork"
}

variable "subnetwork_ip_cidr_range" {
  type        = string
  description = "The IP CIDR range of the subnetwork"
  default     = "10.10.0.0/16"
}

variable "subnetwork_private_ip_google_access" {
  type        = bool
  description = "When set to true, private IP Google access will be enabled"
  default     = true
}

/* 
** ******************************************************
** Database VPC Connection
** ******************************************************
*/

variable "private_ip_address_name" {
  type        = string
  description = "The name of the private IP address"
  default     = "keycloak-db-private-ip"
}

/* 
** ******************************************************
** Database Instance
** ******************************************************
*/

variable "db_instance_name" {
  type        = string
  description = "The name of the database instance"
  default     = "keycloak-instance"
}

variable "db_version" {
  type        = string
  description = "The version of of the database"
  default     = "POSTGRES_17"
}

variable "db_deletion_protection" {
  type        = bool
  description = "When set to true, deletion of the instance is prevented."
  default     = false
}

/* 
** ******************************************************
** Database Instance - Settings
** ******************************************************
*/

variable "db_tier" {
  type        = string
  description = "The machine tier (First Generation) or type (Second Generation). Reference: https://cloud.google.com/sql/pricing"
  default     = "db-perf-optimized-N-2"
}

variable "db_edition" {
  type        = string
  description = "The machine edition"
  default     = "ENTERPRISE_PLUS"
}

variable "db_activation_policy" {
  type        = string
  description = "Specifies when the instance should be active. Options are ALWAYS, NEVER or ON_DEMAND"
  default     = "ALWAYS"
}

variable "db_availability_type" {
  type        = string
  description = "The availability type of the database instance"
  default     = "REGIONAL"
}

variable "db_connector_enforcement" {
  type        = string
  description = "The enforcement of the connector"
  default     = "NOT_REQUIRED"
}

variable "db_disk_autoresize" {
  type        = string
  description = "Second Generation only. Configuration to increase storage size automatically."
  default     = true
}

variable "db_disk_type" {
  type        = string
  description = "Second generation only. The type of data disk: PD_SSD or PD_HDD"
  default     = "PD_SSD"
}

variable "db_pricing_plan" {
  type        = string
  description = "First generation only. Pricing plan for this instance, can be one of PER_USE or PACKAGE"
  default     = "PER_USE"
}

/* 
** ******************************************************
** Database Instance - Insights Config
** ******************************************************
*/

variable "db_query_insights_enabled" {
  type        = bool
  description = "When set to true, query insights will be enabled"
  default     = true
}

variable "db_query_plans_per_minute" {
  type        = number
  description = "The number of query plans per minute to record"
  default     = 20
}

variable "db_query_string_length" {
  type        = number
  description = "The length of the query string to record"
  default     = 4096
}

variable "db_record_application_tags" {
  type        = bool
  description = "When set to true, application tags will be recorded"
  default     = false
}

variable "db_record_client_address" {
  type        = bool
  description = "When set to true, client address will be recorded"
  default     = false
}

/* 
** ******************************************************
** Database Instance - Maintenance Window
** ******************************************************
*/

variable "db_maintenance_window_day" {
  type        = number
  description = "The day of the week to perform maintenance"
  default     = 7
}

variable "db_maintenance_window_hour" {
  type        = number
  description = "The hour of the day to perform maintenance"
  default     = 3
}

/* 
** ******************************************************
** Database Instance - Backup Configuration
** ******************************************************
*/

variable "db_backup_enabled" {
  type        = bool
  description = "When set to true, backups will be enabled"
  default     = true
}

variable "db_backup_start_time" {
  type        = string
  description = "The start time of the backup"
  default     = "00:00"
}

variable "db_point_in_time_recovery_enabled" {
  type        = bool
  description = "When set to true, point in time recovery will be enabled"
  default     = true
}

variable "db_transaction_log_retention_days" {
  type        = number
  description = "The number of days to retain transaction logs"
  default     = 7
}

variable "db_backup_retention_count" {
  type        = number
  description = "The number of backups to retain"
  default     = 15
}

variable "db_backup_retention_unit" {
  type        = string
  description = "The unit of time for the backup retention"
  default     = "COUNT"
}

/* 
** ******************************************************
** Database Instance - IP Configuration
** ******************************************************
*/

variable "public_ipv4_enabled" {
  type        = bool
  description = "When enabled a public IP will be assigned to the database instance and allow connection using Cloud SQL Proxy"
  default     = false
}

variable "db_enable_private_path_for_google_cloud_services" {
  type        = bool
  description = "When enabled, private path for Google Cloud Services will be enabled"
  default     = false
}

/* 
** ******************************************************
** Database
** ******************************************************
*/

variable "db_name" {
  type        = string
  description = "Name of the default database to create"
  default     = "keycloak"
}

variable "db_charset" {
  type        = string
  description = "The charset for the default database"
  default     = "UTF8"
}

variable "db_collation" {
  type        = string
  description = "The collation for the default database."
  default     = "en_US.UTF8"
}

/* 
** ******************************************************
** Database - User
** ******************************************************
*/

variable "db_user_name" {
  type        = string
  description = "The name of the default user"
  default     = "postgres"
}

# access settings
variable "db_read_users" {
  type        = set(string)
  description = "Set of users that will have access read to ALL SQL databases"
  default     = []
}

variable "db_write_users" {
  type        = set(string)
  description = "Set of users that will have access read & write to ALL SQL databases"
  default     = []
}

/* 
** ******************************************************
** Keycloak - Cluster
** ******************************************************
*/

variable "keycloak_image_project_id" {
  type        = string
  description = "The GCP project ID where the Keycloak container image is hosted"
}

variable "keycloak_cluster_name" {
  type        = string
  description = "The name of the Keycloak GKE cluster"
  default     = "keycloak-cluster"
}

variable "keycloak_cluster_deletion_protection" {
  type        = bool
  description = "When set to true, deletion of the Keycloak GKE cluster is prevented."
  default     = false
}

variable "keycloak_cluster_enable_autopilot" {
  type        = bool
  description = "When set to true, Keycloak GKE cluster Autopilot mode will be enabled"
  default     = true
}

/* 
** ******************************************************
** Keycloak - GCP Service Account
** ******************************************************
*/

variable "keycloak_google_service_account_name" {
  type        = string
  description = "The name of the Keycloak GCP service account"
  default     = "keycloak-gsa"
}

variable "keycloak_google_service_account_display_name" {
  type        = string
  description = "The display name of the Keycloak GCP service account"
  default     = "Keycloak GCP Service Account"
}

variable "keycloak_google_service_account_roles" {
  type        = set(string)
  description = "Set of IAM roles to assign to the Keycloak GCP service account"
  default = [
    "roles/cloudsql.client",
    "roles/iam.serviceAccountUser",
    "roles/compute.networkUser",
  ]
}

/* 
** ******************************************************
** Keycloak - Keycloak Namespace
** ******************************************************
*/

variable "keycloak_namespace_name" {
  type        = string
  description = "The name of the Keycloak Kubernetes namespace"
  default     = "keycloak"
}

/* 
** ******************************************************
** Keycloak - Kubernetes Service Account
** ******************************************************
*/

variable "keycloak_k8s_service_account_name" {
  type        = string
  description = "The name of the Keycloak Kubernetes service account"
  default     = "keycloak-ksa"
}

/* 
** ******************************************************
** Keycloak - Frontend Configuration
** ******************************************************
*/

variable "ssl_policy_name" {
  type        = string
  description = "The name of the SSL policy to attach to the Frontend Configuration"
  default     = "keycloak-ssl-policy"
}

variable "ssl_policy_profile" {
  type        = string
  description = "The profile of the SSL policy to attach to the Frontend Configuration"
  default     = "MODERN"
}

variable "frontend_config_name" {
  type        = string
  description = "The name of the Frontend Configuration"
  default     = "keycloak-frontend-config"
}

/* 
** ******************************************************
** Keycloak - Managed Certificate
** ******************************************************
*/

variable "managed_certificate_name" {
  type        = string
  description = "The name of the Managed Certificate"
  default     = "keycloak-managed-certificate"
}

variable "managed_certificate_host" {
  type        = string
  description = "Host for the Managed Certificate"
}

/* 
** ******************************************************
** Keycloak - Backend Config
** ******************************************************
*/

variable "backend_config_name" {
  type        = string
  description = "The name of the Backend Configuration"
  default     = "keycloak-backend-config"
}

/* 
** ******************************************************
** Keycloak - Ingress
** ******************************************************
*/

variable "public_ip_address_name" {
  type        = string
  description = "The name of the public IP address for the Ingress"
  default     = "keycloak-public-ip"
}

variable "public_ip_address_type" {
  type        = string
  description = "The type of the public IP address for the Ingress"
  default     = "EXTERNAL"
}

variable "ingress_name" {
  type        = string
  description = "The name of the Ingress resource"
  default     = "keycloak-ingress"
}

/* 
** ******************************************************
** Keycloak - Deploy Steps
** ******************************************************
*/

variable "deploy_k8s_grants" {
  type        = bool
  description = "When set to true, Kubernetes service account grants will be deployed"
  default     = true
}

variable "deploy_k8s_resources" {
  type        = bool
  description = "When set to true, Kubernetes resources will be deployed"
  default     = true
}
