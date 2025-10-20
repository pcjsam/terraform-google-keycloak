# Infrastructure Module

This Terraform module creates the foundational Google Cloud Platform (GCP) infrastructure required for running Keycloak on GKE. It provisions networking, database, Kubernetes cluster, and IAM resources.

## Overview

The infrastructure module is responsible for creating all GCP-level resources that serve as the foundation for the Keycloak deployment. This module is designed to be deployed first, with its outputs then used to configure providers and deploy the application module.

## Resources Created

This module creates the following GCP resources:

### Networking
- **VPC Network**: Custom VPC network for secure isolation
- **Subnet**: Private subnet within the VPC with configurable IP range
- **Private IP Address**: Global address for VPC peering
- **VPC Peering Connection**: Service networking connection for Cloud SQL private access
- **Public IP Address**: Global static IP for the ingress load balancer

### Database
- **Cloud SQL PostgreSQL Instance**: Fully managed PostgreSQL database with:
  - Private IP connectivity only (by default)
  - IAM authentication enabled
  - Automated backups with point-in-time recovery
  - Query insights enabled
  - Configurable machine tier and edition
- **Database**: Default Keycloak database
- **Database Users**:
  - Default PostgreSQL user
  - IAM-authenticated users for read/write access
  - IAM service account user for Keycloak

### Kubernetes
- **GKE Autopilot Cluster**: Managed Kubernetes cluster with:
  - VPC-native networking
  - Secret Manager integration
  - Logging enabled
  - Workload Identity support
- **Cluster Readiness Check**: Ensures cluster is fully operational before completion

### IAM & Security
- **Keycloak GCP Service Account**: Service account for Keycloak with:
  - Cloud SQL Client role
  - Service Account User role
  - Compute Network User role
- **IAM Bindings**: Grants for database access and artifact registry
- **SSL Policy**: Configurable SSL policy for frontend (default: MODERN)

## Required Providers

```hcl
terraform {
  required_version = ">= 1.9.8"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.39.0"
    }
  }
}
```

## Usage

### Basic Usage

```hcl
module "keycloak_infrastructure" {
  source = "./modules/infrastructure"

  # Project Configuration
  project = "my-gcp-project"
  region  = "us-central1"
  number  = "123456789012"

  # Keycloak Configuration
  keycloak_image_project_id = "my-gcp-project"
}
```

### Production Usage

```hcl
module "keycloak_infrastructure" {
  source = "./modules/infrastructure"

  # Project Configuration
  project = "my-gcp-project"
  region  = "us-central1"
  number  = "123456789012"

  # Network Configuration
  network_name                     = "keycloak-prod-network"
  subnetwork_name                  = "keycloak-prod-subnet"
  subnetwork_ip_cidr_range         = "10.10.0.0/16"
  subnetwork_private_ip_google_access = true

  # Database Configuration
  db_instance_name       = "keycloak-prod-db"
  db_version             = "POSTGRES_17"
  db_deletion_protection = true
  db_tier                = "db-perf-optimized-N-4"
  db_edition             = "ENTERPRISE_PLUS"
  db_availability_type   = "REGIONAL"

  # Database Access
  db_read_users  = ["readonly@example.com"]
  db_write_users = ["admin@example.com"]

  # Keycloak Configuration
  keycloak_image_project_id            = "my-gcp-project"
  keycloak_cluster_name                = "keycloak-prod-cluster"
  keycloak_cluster_deletion_protection = true
  keycloak_google_service_account_name = "keycloak-prod-sa"

  # SSL Configuration
  ssl_policy_name    = "keycloak-prod-ssl"
  ssl_policy_profile = "MODERN"
}
```

## Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `project` | string | GCP project ID |
| `region` | string | GCP region for resources |
| `number` | string | GCP project number |
| `keycloak_image_project_id` | string | GCP project ID where Keycloak container image is hosted |

### Network Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `network_name` | string | `"keycloak-network"` | VPC network name |
| `network_auto_create_subnetworks` | bool | `false` | Auto-create subnetworks |
| `subnetwork_name` | string | `"keycloak-subnetwork"` | Subnetwork name |
| `subnetwork_ip_cidr_range` | string | `"10.10.0.0/16"` | Subnetwork IP CIDR range |
| `subnetwork_private_ip_google_access` | bool | `true` | Enable private Google access |
| `private_ip_address_name` | string | `"keycloak-db-private-ip"` | Private IP address name for VPC peering |

### Database Instance Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `db_instance_name` | string | `"keycloak-instance"` | Database instance name |
| `db_version` | string | `"POSTGRES_17"` | PostgreSQL version |
| `db_deletion_protection` | bool | `false` | Prevent database deletion |
| `db_tier` | string | `"db-perf-optimized-N-2"` | Database machine tier |
| `db_edition` | string | `"ENTERPRISE_PLUS"` | Database edition |
| `db_activation_policy` | string | `"ALWAYS"` | Instance activation policy |
| `db_availability_type` | string | `"REGIONAL"` | Database availability type |
| `db_connector_enforcement` | string | `"NOT_REQUIRED"` | Connector enforcement |
| `db_disk_autoresize` | bool | `true` | Auto-resize disk |
| `db_disk_type` | string | `"PD_SSD"` | Disk type |
| `db_pricing_plan` | string | `"PER_USE"` | Pricing plan |

### Database Insights Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `db_query_insights_enabled` | bool | `true` | Enable query insights |
| `db_query_plans_per_minute` | number | `20` | Query plans per minute |
| `db_query_string_length` | number | `4096` | Query string length |
| `db_record_application_tags` | bool | `false` | Record application tags |
| `db_record_client_address` | bool | `false` | Record client address |

### Database Maintenance Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `db_maintenance_window_day` | number | `7` | Maintenance day (1=Monday, 7=Sunday) |
| `db_maintenance_window_hour` | number | `3` | Maintenance hour (0-23) |

### Database Backup Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `db_backup_enabled` | bool | `true` | Enable backups |
| `db_backup_start_time` | string | `"00:00"` | Backup start time |
| `db_point_in_time_recovery_enabled` | bool | `true` | Enable point-in-time recovery |
| `db_transaction_log_retention_days` | number | `7` | Transaction log retention days |
| `db_backup_retention_count` | number | `15` | Number of backups to retain |
| `db_backup_retention_unit` | string | `"COUNT"` | Backup retention unit |

### Database IP Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `public_ipv4_enabled` | bool | `false` | Enable public IPv4 |
| `db_enable_private_path_for_google_cloud_services` | bool | `false` | Enable private path for Google Cloud services |

### Database Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `db_name` | string | `"keycloak"` | Database name |
| `db_charset` | string | `"UTF8"` | Database charset |
| `db_collation` | string | `"en_US.UTF8"` | Database collation |
| `db_user_name` | string | `"postgres"` | Default database user |
| `db_read_users` | set(string) | `[]` | Users with read-only access |
| `db_write_users` | set(string) | `[]` | Users with read-write access |

### Keycloak Cluster Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `keycloak_cluster_name` | string | `"keycloak-cluster"` | GKE cluster name |
| `keycloak_cluster_deletion_protection` | bool | `false` | Prevent cluster deletion |
| `keycloak_cluster_enable_autopilot` | bool | `true` | Enable GKE Autopilot mode |

### Keycloak Service Account Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `keycloak_google_service_account_name` | string | `"keycloak-gsa"` | Keycloak GCP service account name |
| `keycloak_google_service_account_display_name` | string | `"Keycloak GCP Service Account"` | Display name |
| `keycloak_google_service_account_roles` | set(string) | `["roles/cloudsql.client", "roles/iam.serviceAccountUser", "roles/compute.networkUser"]` | IAM roles |

### SSL Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ssl_policy_name` | string | `"keycloak-ssl-policy"` | SSL policy name |
| `ssl_policy_profile` | string | `"MODERN"` | SSL policy profile |

### Ingress Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `public_ip_address_name` | string | `"keycloak-public-ip"` | Public IP address name |
| `public_ip_address_type` | string | `"EXTERNAL"` | Public IP address type |

## Outputs

### Network Outputs

| Output | Type | Description |
|--------|------|-------------|
| `network_id` | string | VPC network ID |
| `subnetwork_id` | string | Subnetwork ID |

### Database Outputs

| Output | Type | Sensitive | Description |
|--------|------|-----------|-------------|
| `cloud_sql_connection_name` | string | No | Cloud SQL connection name for provider configuration |
| `cloud_sql_instance_name` | string | No | Cloud SQL instance name |
| `cloud_sql_service_account_email` | string | No | Cloud SQL service account email |
| `cloud_sql_database_name` | string | No | Cloud SQL database name |
| `cloud_sql_database_username` | string | No | Cloud SQL database username |
| `cloud_sql_database_password` | string | Yes | Cloud SQL database password |

### Keycloak Cluster Outputs

| Output | Type | Sensitive | Description |
|--------|------|-----------|-------------|
| `keycloak_cluster_name` | string | No | GKE cluster name |
| `keycloak_cluster_endpoint` | string | No | GKE cluster endpoint for Kubernetes provider configuration |
| `keycloak_cluster_access_token` | string | Yes | Access token for Kubernetes provider configuration |
| `keycloak_cluster_ca_certificate` | string | No | CA certificate for Kubernetes provider configuration |
| `keycloak_gcp_service_account_email` | string | No | Keycloak GCP service account email |

### Ingress Outputs

| Output | Type | Description |
|--------|------|-------------|
| `keycloak_ingress_public_ip` | string | Static IP address for ingress configuration |

## Features

### High Availability

The module supports high availability configurations:

- **Regional Cloud SQL**: Set `db_availability_type = "REGIONAL"` for automatic failover
- **Automated Backups**: Enabled by default with 15-day retention
- **Point-in-Time Recovery**: 7-day transaction log retention
- **GKE Autopilot**: Managed Kubernetes with automatic scaling and updates

### Security

Security features include:

- **Private Networking**: Database uses private IP only by default
- **IAM Authentication**: Database supports IAM-based authentication
- **Workload Identity**: Ready for Kubernetes service account binding
- **Modern SSL**: Configurable SSL policy with MODERN profile default
- **Network Isolation**: Dedicated VPC with private subnet

### Monitoring

Built-in monitoring capabilities:

- **Query Insights**: Enabled by default on Cloud SQL
- **GKE Logging**: Kubernetes logging to Cloud Logging
- **Resource Metrics**: Standard GCP monitoring for all resources

## Dependencies

### Resource Dependencies

The module manages the following dependencies automatically:

1. VPC and subnet must exist before Cloud SQL
2. Service networking connection required for Cloud SQL private IP
3. GKE cluster depends on VPC/subnet configuration
4. Cluster readiness check ensures cluster is operational before completion
5. Service accounts must exist before IAM bindings

### External Dependencies

Before deploying this module:

1. Enable required GCP APIs:
   - Compute Engine API
   - Container API
   - Cloud SQL Admin API
   - Service Networking API
   - Certificate Manager API
   - Secret Manager API

2. Have sufficient project quotas for:
   - Compute instances
   - Static IP addresses
   - Cloud SQL instances
   - GKE clusters

## Notes

### Cluster Readiness

The module includes a readiness check that waits for the GKE cluster to be fully operational before marking the deployment as complete. This ensures that:

- The cluster is in RUNNING state
- The API server is accepting connections
- Credentials can be obtained

This prevents issues when immediately trying to deploy Kubernetes resources.

### Database Password

The default database user password is set to `"change_me"` with lifecycle ignore_changes. In production:

1. Change the password immediately after creation
2. Store the password in Secret Manager
3. The lifecycle rule prevents Terraform from reverting your changes

### IAM Users

For `db_read_users` and `db_write_users`:

- Users must be valid Google Cloud identity emails
- Users are granted Cloud SQL Client and Instance User roles
- IAM authentication is enabled for these users
- Actual database grants (CONNECT, SELECT, etc.) are managed by the application module

## Best Practices

1. **Production Deployments**:
   - Enable deletion protection for database and cluster
   - Use REGIONAL availability for high availability
   - Configure appropriate machine tiers based on workload
   - Enable all backup and recovery features

2. **Security**:
   - Keep `public_ipv4_enabled = false` for databases
   - Use IAM authentication for database access
   - Review and customize service account roles
   - Use VPC peering for private connectivity

3. **Networking**:
   - Choose appropriate CIDR ranges to avoid conflicts
   - Enable private Google access for API connectivity
   - Reserve IP ranges for future expansion

4. **Cost Optimization**:
   - Choose appropriate database tier for workload
   - Consider using ZONAL availability for non-production
   - Review backup retention settings
   - Monitor query insights for optimization opportunities

## Troubleshooting

### Cluster Creation Issues

If cluster creation fails:
- Check project quotas for GKE resources
- Verify subnet has enough IP addresses
- Ensure Compute Engine API is enabled

### Database Connection Issues

If Cloud SQL connection fails:
- Verify VPC peering is established
- Check that private IP range doesn't conflict
- Ensure Service Networking API is enabled

### IAM Permission Issues

If IAM binding fails:
- Verify you have Project IAM Admin role
- Check that service accounts exist
- Ensure identities are valid Google Cloud accounts
