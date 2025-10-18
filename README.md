# Terraform Google Keycloak Module

This Terraform module deploys a production-ready Keycloak instance on Google Cloud Platform (GCP) using Google Kubernetes Engine (GKE) Autopilot with a Cloud SQL PostgreSQL database.

## Architecture Overview

The module creates the following infrastructure:

- **VPC Network**: Custom VPC with private subnet for secure networking
- **Cloud SQL PostgreSQL**: Fully managed PostgreSQL database with private IP
- **GKE Autopilot Cluster**: Managed Kubernetes cluster for running Keycloak
- **Keycloak Deployment**: Keycloak instance deployed using the Keycloak Operator
- **Cloud SQL Proxy**: Sidecar container for secure database connectivity with IAM authentication
- **Load Balancer & Ingress**: HTTPS ingress with Google-managed SSL certificates
- **Workload Identity**: Secure GCP service account binding to Kubernetes service accounts
- **IAM Roles**: Proper IAM bindings for database and Artifact Registry access

## Prerequisites

Before using this module, ensure you have:

1. A GCP project with billing enabled
2. Terraform >= 1.9.8 installed
3. The following GCP APIs enabled (the module can enable them for you):
   - Cloud Resource Manager API (`cloudresourcemanager.googleapis.com`)
   - Secret Manager API (`secretmanager.googleapis.com`)
   - Compute Engine API (`compute.googleapis.com`)
   - Certificate Manager API (`certificatemanager.googleapis.com`)
   - Kubernetes Engine API (`container.googleapis.com`)
   - Service Networking API (`servicenetworking.googleapis.com`)
   - Cloud SQL Admin API (`sqladmin.googleapis.com`)
   - VPC Access API (`vpcaccess.googleapis.com`)
4. A Keycloak container image stored in Artifact Registry or Container Registry
5. A domain name for Keycloak and DNS access to create an A record

## Required Providers

This module requires the following Terraform providers:

```hcl
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
```

## Provider Configuration

### Required Data Sources

The following data sources are required for provider configuration:

```hcl
# Secret Manager secret containing the database password
data "google_secret_manager_secret_version_access" "keycloak_db_password" {
  secret  = "KEYCLOAK_DB_PASSWORD"
  project = var.project_id
}

# GKE cluster for Kubernetes provider
data "google_container_cluster" "keycloak_cluster" {
  name     = module.keycloak.keycloak_gke_cluster_name
  location = var.project_region

  depends_on = [module.keycloak]
}

# Current GCP client configuration
data "google_client_config" "current" {}
```

### Provider Configuration Example

```hcl
provider "google" {
  project = var.project_id
  region  = var.project_region
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.keycloak_cluster.endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.keycloak_cluster.master_auth[0].cluster_ca_certificate)
}

provider "kubectl" {
  host                   = "https://${data.google_container_cluster.keycloak_cluster.endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.keycloak_cluster.master_auth[0].cluster_ca_certificate)
  load_config_file       = false
}

provider "postgresql" {
  scheme      = "gcppostgres"
  host        = module.keycloak.cloud_sql_connection_name
  username    = module.keycloak.cloud_sql_database_username
  password    = data.google_secret_manager_secret_version_access.keycloak_db_password.secret_data
  superuser   = false
}

provider "http" {
  # No configuration required - used to fetch remote YAML manifests
}
```

## Usage Example

### Basic Usage

```hcl
module "keycloak" {
  source = "./terraform-google-keycloak"

  # Project Configuration
  project = "my-gcp-project"
  region  = "us-central1"
  number  = "123456789012" # Your GCP project number

  # Keycloak Configuration
  keycloak_image_project_id   = "my-gcp-project"
  keycloak_image              = "us-central1-docker.pkg.dev/my-gcp-project/keycloak/keycloak:26.3.3"
  keycloak_image_tag          = "26.3.3"
  managed_certificate_host    = "keycloak.example.com"

  # Optional: Database Configuration
  db_tier              = "db-perf-optimized-N-2"
  db_edition           = "ENTERPRISE_PLUS"
  db_availability_type = "REGIONAL"

  # Optional: Database Access
  db_read_users  = ["user1@example.com"]
  db_write_users = ["user2@example.com"]
}
```

### Complete Example with All Options

```hcl
module "keycloak" {
  source = "./terraform-google-keycloak"

  # Project Configuration
  project = "my-gcp-project"
  region  = "us-central1"
  number  = "123456789012"

  # Network Configuration
  network_name                       = "keycloak-network"
  network_auto_create_subnetworks    = false
  subnetwork_name                    = "keycloak-subnetwork"
  subnetwork_ip_cidr_range           = "10.10.0.0/16"
  subnetwork_private_ip_google_access = true

  # Database Configuration
  db_instance_name                    = "keycloak-instance"
  db_version                          = "POSTGRES_17"
  db_deletion_protection              = true
  db_tier                             = "db-perf-optimized-N-2"
  db_edition                          = "ENTERPRISE_PLUS"
  db_availability_type                = "REGIONAL"
  db_name                             = "keycloak"
  db_charset                          = "UTF8"
  db_collation                        = "en_US.UTF8"

  # Database Access
  db_read_users  = ["readonly@example.com"]
  db_write_users = ["admin@example.com"]

  # Keycloak Configuration
  keycloak_image_project_id               = "my-gcp-project"
  keycloak_image                          = "us-central1-docker.pkg.dev/my-gcp-project/keycloak/keycloak:26.3.3"
  keycloak_image_tag                      = "26.3.3"
  keycloak_cluster_name                   = "keycloak-cluster"
  keycloak_cluster_deletion_protection    = true
  keycloak_cluster_enable_autopilot       = true
  keycloak_namespace_name                 = "keycloak"

  # SSL & Ingress Configuration
  managed_certificate_host = "keycloak.example.com"
  ssl_policy_profile       = "MODERN"

  # Deployment Options
  deploy_k8s_grants    = true
  deploy_k8s_resources = true
}
```

## Required API Services

The module requires the following Google Cloud APIs to be enabled:

```hcl
locals {
  services = [
    "cloudresourcemanager.googleapis.com",
    "secretmanager.googleapis.com",
    "compute.googleapis.com",
    "certificatemanager.googleapis.com",
    "container.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "vpcaccess.googleapis.com",
  ]
}

resource "google_project_service" "services" {
  for_each = toset(local.services)
  project  = var.project_id
  service  = each.value
}
```

## Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `project` | string | GCP project ID |
| `region` | string | GCP region for resources |
| `number` | string | GCP project number |
| `keycloak_image_project_id` | string | GCP project ID where Keycloak image is hosted |
| `keycloak_image` | string | Full Keycloak container image path |
| `keycloak_image_tag` | string | Keycloak container image tag |
| `managed_certificate_host` | string | Domain name for the managed SSL certificate |

### Optional Variables

#### Network Configuration
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `network_name` | string | `"keycloak-network"` | VPC network name |
| `network_auto_create_subnetworks` | bool | `false` | Auto-create subnetworks |
| `subnetwork_name` | string | `"keycloak-subnetwork"` | Subnetwork name |
| `subnetwork_ip_cidr_range` | string | `"10.10.0.0/16"` | Subnetwork IP CIDR range |
| `subnetwork_private_ip_google_access` | bool | `true` | Enable private Google access |

#### Database Configuration
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `db_instance_name` | string | `"keycloak-instance"` | Database instance name |
| `db_version` | string | `"POSTGRES_17"` | PostgreSQL version |
| `db_deletion_protection` | bool | `false` | Prevent database deletion |
| `db_tier` | string | `"db-perf-optimized-N-2"` | Database machine tier |
| `db_edition` | string | `"ENTERPRISE_PLUS"` | Database edition |
| `db_availability_type` | string | `"REGIONAL"` | Database availability type |
| `db_name` | string | `"keycloak"` | Database name |
| `db_charset` | string | `"UTF8"` | Database charset |
| `db_collation` | string | `"en_US.UTF8"` | Database collation |
| `db_user_name` | string | `"postgres"` | Default database user |
| `db_read_users` | set(string) | `[]` | Users with read-only access |
| `db_write_users` | set(string) | `[]` | Users with read-write access |

#### Keycloak Configuration
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `keycloak_cluster_name` | string | `"keycloak-cluster"` | GKE cluster name |
| `keycloak_cluster_deletion_protection` | bool | `false` | Prevent cluster deletion |
| `keycloak_cluster_enable_autopilot` | bool | `true` | Enable GKE Autopilot mode |
| `keycloak_namespace_name` | string | `"keycloak"` | Kubernetes namespace |
| `keycloak_k8s_service_account_name` | string | `"keycloak-ksa"` | Kubernetes service account name |
| `keycloak_google_service_account_name` | string | `"keycloak-gsa"` | GCP service account name |

#### SSL & Ingress Configuration
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ssl_policy_name` | string | `"keycloak-ssl-policy"` | SSL policy name |
| `ssl_policy_profile` | string | `"MODERN"` | SSL policy profile |
| `frontend_config_name` | string | `"keycloak-frontend-config"` | Frontend config name |
| `managed_certificate_name` | string | `"keycloak-managed-certificate"` | Managed certificate name |
| `backend_config_name` | string | `"keycloak-backend-config"` | Backend config name |
| `ingress_name` | string | `"keycloak-ingress"` | Ingress resource name |
| `public_ip_address_name` | string | `"keycloak-public-ip"` | Public IP address name |

#### Deployment Options
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `deploy_k8s_grants` | bool | `true` | Deploy PostgreSQL grants |
| `deploy_k8s_resources` | bool | `true` | Deploy Kubernetes resources |

## Outputs

| Output | Description |
|--------|-------------|
| `network_id` | VPC network ID |
| `subnetwork_id` | Subnetwork ID |
| `cloud_sql_connection_name` | Cloud SQL connection name |
| `cloud_sql_instance_name` | Cloud SQL instance name |
| `cloud_sql_service_account_email` | Cloud SQL service account email |
| `cloud_sql_database_name` | Cloud SQL database name |
| `cloud_sql_database_username` | Cloud SQL database username |
| `keycloak_gcp_service_account_email` | Keycloak GCP service account email |

## Deployment Steps

### 1. Enable Required APIs

First, ensure all required Google Cloud APIs are enabled. You can use the included code snippet in your Terraform configuration.

### 2. Create Secret Manager Secret

Create a secret in Secret Manager for the database password:

```bash
echo -n "your-secure-password" | gcloud secrets create KEYCLOAK_DB_PASSWORD \
  --data-file=- \
  --project=your-project-id
```

### 3. Build and Push Keycloak Image

Build and push your Keycloak image to Artifact Registry or Container Registry:

```bash
docker build -t us-central1-docker.pkg.dev/your-project/keycloak/keycloak:26.3.3 .
docker push us-central1-docker.pkg.dev/your-project/keycloak/keycloak:26.3.3
```

### 4. Configure Providers

Create a `providers.tf` file with the configuration shown in the Provider Configuration section above.

### 5. Apply Terraform Configuration

Initialize and apply the Terraform configuration:

```bash
terraform init
terraform plan
terraform apply
```

### 6. Configure DNS

After deployment, get the public IP address and configure your DNS:

```bash
terraform output ingress_public_ip
```

Create an A record pointing `keycloak.example.com` to the output IP address.

### 7. Wait for Certificate Provisioning

Google-managed certificates can take up to 15 minutes to provision. Monitor the certificate status:

```bash
kubectl get managedcertificate -n keycloak
```

## How It Works

### Architecture Components

1. **Networking Layer**
   - Creates a custom VPC network with a private subnet
   - Configures VPC peering for Cloud SQL private connectivity
   - Allocates a global static IP for the load balancer

2. **Database Layer**
   - Deploys a Cloud SQL PostgreSQL instance with private IP
   - Configures IAM authentication for secure, password-less connections
   - Sets up automated backups and point-in-time recovery
   - Creates database grants for specified read/write users

3. **Kubernetes Layer**
   - Deploys a GKE Autopilot cluster for simplified operations
   - Creates a dedicated namespace for Keycloak resources
   - Installs Keycloak CRDs and the Keycloak Operator
   - Configures Workload Identity for secure GCP service account binding

4. **Keycloak Deployment**
   - Uses the Keycloak Operator to manage the Keycloak instance
   - Deploys Cloud SQL Proxy as an init container for database connectivity
   - Configures health checks and metrics endpoints
   - Sets up bootstrap admin credentials via Kubernetes secrets

5. **Ingress & SSL**
   - Creates a Google-managed SSL certificate for automatic renewal
   - Configures an HTTPS load balancer with HTTP-to-HTTPS redirect
   - Sets up custom health checks and backend configuration
   - Applies modern SSL policies for security

### Authentication Flow

1. Keycloak pods use Workload Identity to authenticate as a GCP service account
2. The Cloud SQL Proxy authenticates to Cloud SQL using IAM authentication
3. No database passwords are required - authentication is handled via IAM tokens
4. The bootstrap admin secret is stored in Kubernetes and mounted to Keycloak pods

### Security Features

- **Private Database**: Cloud SQL instance only accessible via private IP
- **IAM Authentication**: Password-less database authentication using IAM
- **Workload Identity**: Secure binding between Kubernetes and GCP service accounts
- **Network Isolation**: Resources deployed in a private VPC network
- **HTTPS Only**: Automatic HTTP-to-HTTPS redirect with modern SSL policies
- **Managed Certificates**: Automatic SSL certificate provisioning and renewal

## Troubleshooting

### Certificate Not Provisioning

If the managed certificate stays in "Provisioning" state:
- Verify DNS A record points to the correct IP address
- Check that the domain is publicly resolvable
- Ensure the Ingress resource is correctly configured
- Wait up to 15 minutes for initial provisioning

### Keycloak Pod Not Starting

If Keycloak pods fail to start:
- Check Cloud SQL Proxy logs: `kubectl logs -n keycloak <pod-name> -c cloud-sql-proxy`
- Verify Workload Identity binding is correct
- Ensure the GCP service account has `roles/cloudsql.client` role
- Check database grants are properly configured

### Database Connection Issues

If Keycloak cannot connect to the database:
- Verify the Cloud SQL instance is running
- Check the database password in Secret Manager
- Ensure the postgresql provider configuration is correct
- Verify IAM authentication is enabled on the Cloud SQL instance

### Image Pull Errors

If the cluster cannot pull the Keycloak image:
- Verify the image path is correct
- Ensure the Compute Engine default service account has `roles/artifactregistry.reader`
- Check that the image exists in Artifact Registry
- Verify the image project ID is correctly configured

## Best Practices

1. **Enable Deletion Protection**: Set `db_deletion_protection = true` and `keycloak_cluster_deletion_protection = true` in production
2. **Use Regional Availability**: Configure `db_availability_type = "REGIONAL"` for high availability
3. **Regular Backups**: The module configures automated backups with 7-day transaction log retention
4. **Monitor Resources**: Enable Cloud Monitoring and Cloud Logging for visibility
5. **Security Scanning**: Regularly scan your Keycloak container images for vulnerabilities
6. **Rotate Credentials**: Periodically rotate the bootstrap admin password
7. **Use Private IPs**: Keep `public_ipv4_enabled = false` for enhanced security
8. **Version Pinning**: Pin provider and module versions for reproducible deployments

## License

This module is provided as-is for use in deploying Keycloak on Google Cloud Platform.

## Contributing

Contributions are welcome! Please ensure all changes are tested and documented.

## Support

For issues and questions:
- Check the Troubleshooting section above
- Review Keycloak documentation: https://www.keycloak.org/documentation
- Review GKE Autopilot documentation: https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview
- Review Cloud SQL documentation: https://cloud.google.com/sql/docs
