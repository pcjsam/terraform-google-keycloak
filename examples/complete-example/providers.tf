# ==============================================================================
# TERRAFORM AND PROVIDER CONFIGURATION
# ==============================================================================

terraform {
  required_version = ">= 1.9.8"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.39.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~>1.19.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.22.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5.0"
    }
  }
}

# ==============================================================================
# GOOGLE PROVIDER
# ==============================================================================
# Required for both infrastructure and application modules

provider "google" {
  project = var.project
  region  = var.region
}

# ==============================================================================
# KUBERNETES PROVIDER
# ==============================================================================
# Required for application module
# Uses outputs from the infrastructure module for configuration

provider "kubernetes" {
  host                   = "https://${module.keycloak_infrastructure.keycloak_cluster_endpoint}"
  token                  = module.keycloak_infrastructure.keycloak_cluster_access_token
  cluster_ca_certificate = base64decode(module.keycloak_infrastructure.keycloak_cluster_ca_certificate)
}

# ==============================================================================
# KUBECTL PROVIDER
# ==============================================================================
# Required for application module to apply CRDs and other resources
# Uses outputs from the infrastructure module for configuration

provider "kubectl" {
  host                   = "https://${module.keycloak_infrastructure.keycloak_cluster_endpoint}"
  token                  = module.keycloak_infrastructure.keycloak_cluster_access_token
  cluster_ca_certificate = base64decode(module.keycloak_infrastructure.keycloak_cluster_ca_certificate)
  load_config_file       = false
}

# ==============================================================================
# POSTGRESQL PROVIDER
# ==============================================================================
# Required for application module to manage database grants
# Uses outputs from the infrastructure module for configuration

provider "postgresql" {
  scheme    = "gcppostgres"
  host      = module.keycloak_infrastructure.cloud_sql_connection_name
  username  = module.keycloak_infrastructure.cloud_sql_database_username
  password  = module.keycloak_infrastructure.cloud_sql_database_password
  superuser = false
}

# ==============================================================================
# HTTP PROVIDER
# ==============================================================================
# Required for application module to fetch CRD manifests

provider "http" {
  # No configuration required
}
