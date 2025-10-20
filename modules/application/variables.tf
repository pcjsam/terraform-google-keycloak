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

/* 
** ******************************************************
** Database Instance
** ******************************************************
*/

variable "db_instance_name" {
  type        = string
  description = "The name of the Cloud SQL instance"
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

/* 
** ******************************************************
** Database - Writers and readers
** ******************************************************
*/

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
** Keycloak - GCP Service Account
** ******************************************************
*/

variable "keycloak_google_service_account_name" {
  type        = string
  description = "The name of the Keycloak GCP service account"
}

variable "keycloak_google_service_account_email" {
  type        = string
  description = "The email of the Keycloak GCP service account"
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
** Keycloak - CRDs Installation
** ******************************************************
*/

variable "keycloak_crds_version" {
  type        = string
  description = "The version of the Keycloak Operator CRDs to install"
}

/*
** ******************************************************
** Keycloak - Operator Deployment
** ******************************************************
*/

variable "keycloak_operator_version" {
  type        = string
  description = "The version of the Keycloak Operator to deploy"
}

/*
** ******************************************************
** Keycloak - Bootstrap Admin Secret
** ******************************************************
*/

variable "keycloak_bootstrap_admin_secret_name" {
  type        = string
  description = "The name of the Keycloak bootstrap admin secret"
  default     = "bootstrap-admin-secret"
}

/*
** ******************************************************
** Keycloak - Database Secret
** ******************************************************
*/

variable "keycloak_db_secret_name" {
  type        = string
  description = "The name of the Keycloak database secret"
  default     = "db-secret"
}

/*
** ******************************************************
** Keycloak - Instance
** ******************************************************
*/

variable "keycloak_image" {
  type        = string
  description = "The Keycloak container image tag to use"
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

variable "ingress_name" {
  type        = string
  description = "The name of the Ingress resource"
  default     = "keycloak-ingress"
}
