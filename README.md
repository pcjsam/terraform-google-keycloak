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

### Important: Circular Dependency Challenge

This module has a **circular dependency** between provider configuration and resource creation:

- The Kubernetes, kubectl, and PostgreSQL providers need connection information (cluster endpoint, database connection string)
- But these resources are created by the module itself
- Terraform providers are configured **before** any resources are created

This means you **cannot** reference module outputs directly in provider configurations without special handling.

### Required Provider Configuration

Your calling module (root module) **must** configure all required providers. Here's how to handle the circular dependency:

#### Option 1: Two-Stage Apply (Recommended for Production)

**Stage 1:** Create infrastructure without Kubernetes resources
```hcl
# main.tf in your root module
module "keycloak" {
  source = "./terraform-google-keycloak"

  # ... all your variables ...

  # Disable Kubernetes resources on first apply
  deploy_k8s_grants    = false
  deploy_k8s_resources = false
}

provider "google" {
  project = var.project_id
  region  = var.project_region
}

provider "http" {
  # No configuration required
}
```

Apply stage 1:
```bash
terraform apply
```

**Stage 2:** Configure remaining providers and enable Kubernetes resources
```hcl
# After stage 1 completes, add these providers:

data "google_secret_manager_secret_version_access" "keycloak_db_password" {
  secret  = "KEYCLOAK_DB_PASSWORD"
  project = var.project_id
}

provider "kubernetes" {
  host                   = "https://${module.keycloak.keycloak_cluster_endpoint}"
  token                  = module.keycloak.keycloak_cluster_access_token
  cluster_ca_certificate = base64decode(module.keycloak.keycloak_cluster_ca_certificate)
}

provider "kubectl" {
  host                   = "https://${module.keycloak.keycloak_cluster_endpoint}"
  token                  = module.keycloak.keycloak_cluster_access_token
  cluster_ca_certificate = base64decode(module.keycloak.keycloak_cluster_ca_certificate)
  load_config_file       = false
}

provider "postgresql" {
  scheme    = "gcppostgres"
  host      = module.keycloak.cloud_sql_connection_name
  username  = module.keycloak.cloud_sql_database_username
  password  = data.google_secret_manager_secret_version_access.keycloak_db_password.secret_data
  superuser = false
}

# Update module to enable Kubernetes resources
module "keycloak" {
  source = "./terraform-google-keycloak"

  # ... all your variables ...

  # Enable Kubernetes resources on second apply
  deploy_k8s_grants    = true
  deploy_k8s_resources = true
}
```

Apply stage 2:
```bash
terraform apply
```

#### Option 2: Use gcloud for Local Provider Auth (Development/Testing)

Configure providers to use local gcloud credentials instead of module outputs:

```hcl
provider "google" {
  project = var.project_id
  region  = var.project_region
}

data "google_secret_manager_secret_version_access" "keycloak_db_password" {
  secret  = "KEYCLOAK_DB_PASSWORD"
  project = var.project_id
}

# Use exec to get cluster credentials dynamically
provider "kubernetes" {
  host                   = "https://${module.keycloak.keycloak_cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.keycloak.keycloak_cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

provider "kubectl" {
  host                   = "https://${module.keycloak.keycloak_cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.keycloak.keycloak_cluster_ca_certificate)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

provider "postgresql" {
  scheme    = "gcppostgres"
  host      = module.keycloak.cloud_sql_connection_name
  username  = module.keycloak.cloud_sql_database_username
  password  = data.google_secret_manager_secret_version_access.keycloak_db_password.secret_data
  superuser = false
}

provider "http" {
  # No configuration required
}

module "keycloak" {
  source = "./terraform-google-keycloak"

  # ... your variables ...
}
```

**Note:** Option 2 requires `gke-gcloud-auth-plugin` installed and may still encounter timing issues if the cluster isn't fully ready when Terraform tries to apply Kubernetes resources.

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
  keycloak_image              = "us-central1-docker.pkg.dev/my-gcp-project/keycloak/keycloak:26.4"
  keycloak_crds_version       = "26.3.3"
  keycloak_operator_version   = "26.3.3"
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
  keycloak_image                          = "us-central1-docker.pkg.dev/my-gcp-project/keycloak/keycloak:26.4"
  keycloak_crds_version                   = "26.3.3"
  keycloak_operator_version               = "26.3.3"
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

| Variable                    | Type   | Description                                      |
| --------------------------- | ------ | ------------------------------------------------ |
| `project`                   | string | GCP project ID                                   |
| `region`                    | string | GCP region for resources                         |
| `number`                    | string | GCP project number                               |
| `keycloak_image_project_id` | string | GCP project ID where Keycloak image is hosted    |
| `keycloak_image`            | string | Keycloak container image tag to use              |
| `keycloak_crds_version`     | string | Version of the Keycloak Operator CRDs to install |
| `keycloak_operator_version` | string | Version of the Keycloak Operator to deploy       |
| `managed_certificate_host`  | string | Domain name for the managed SSL certificate      |

### Optional Variables

#### Network Configuration

| Variable                              | Type   | Default                 | Description                  |
| ------------------------------------- | ------ | ----------------------- | ---------------------------- |
| `network_name`                        | string | `"keycloak-network"`    | VPC network name             |
| `network_auto_create_subnetworks`     | bool   | `false`                 | Auto-create subnetworks      |
| `subnetwork_name`                     | string | `"keycloak-subnetwork"` | Subnetwork name              |
| `subnetwork_ip_cidr_range`            | string | `"10.10.0.0/16"`        | Subnetwork IP CIDR range     |
| `subnetwork_private_ip_google_access` | bool   | `true`                  | Enable private Google access |

#### Database Configuration

| Variable                 | Type        | Default                   | Description                  |
| ------------------------ | ----------- | ------------------------- | ---------------------------- |
| `db_instance_name`       | string      | `"keycloak-instance"`     | Database instance name       |
| `db_version`             | string      | `"POSTGRES_17"`           | PostgreSQL version           |
| `db_deletion_protection` | bool        | `false`                   | Prevent database deletion    |
| `db_tier`                | string      | `"db-perf-optimized-N-2"` | Database machine tier        |
| `db_edition`             | string      | `"ENTERPRISE_PLUS"`       | Database edition             |
| `db_availability_type`   | string      | `"REGIONAL"`              | Database availability type   |
| `db_name`                | string      | `"keycloak"`              | Database name                |
| `db_charset`             | string      | `"UTF8"`                  | Database charset             |
| `db_collation`           | string      | `"en_US.UTF8"`            | Database collation           |
| `db_user_name`           | string      | `"postgres"`              | Default database user        |
| `db_read_users`          | set(string) | `[]`                      | Users with read-only access  |
| `db_write_users`         | set(string) | `[]`                      | Users with read-write access |

#### Keycloak Configuration

| Variable                               | Type   | Default              | Description                     |
| -------------------------------------- | ------ | -------------------- | ------------------------------- |
| `keycloak_cluster_name`                | string | `"keycloak-cluster"` | GKE cluster name                |
| `keycloak_cluster_deletion_protection` | bool   | `false`              | Prevent cluster deletion        |
| `keycloak_cluster_enable_autopilot`    | bool   | `true`               | Enable GKE Autopilot mode       |
| `keycloak_namespace_name`              | string | `"keycloak"`         | Kubernetes namespace            |
| `keycloak_k8s_service_account_name`    | string | `"keycloak-ksa"`     | Kubernetes service account name |
| `keycloak_google_service_account_name` | string | `"keycloak-gsa"`     | GCP service account name        |

#### SSL & Ingress Configuration

| Variable                   | Type   | Default                          | Description              |
| -------------------------- | ------ | -------------------------------- | ------------------------ |
| `ssl_policy_name`          | string | `"keycloak-ssl-policy"`          | SSL policy name          |
| `ssl_policy_profile`       | string | `"MODERN"`                       | SSL policy profile       |
| `frontend_config_name`     | string | `"keycloak-frontend-config"`     | Frontend config name     |
| `managed_certificate_name` | string | `"keycloak-managed-certificate"` | Managed certificate name |
| `backend_config_name`      | string | `"keycloak-backend-config"`      | Backend config name      |
| `ingress_name`             | string | `"keycloak-ingress"`             | Ingress resource name    |
| `public_ip_address_name`   | string | `"keycloak-public-ip"`           | Public IP address name   |

#### Deployment Options

| Variable               | Type | Default | Description                 |
| ---------------------- | ---- | ------- | --------------------------- |
| `deploy_k8s_grants`    | bool | `true`  | Deploy PostgreSQL grants    |
| `deploy_k8s_resources` | bool | `true`  | Deploy Kubernetes resources |

## Outputs

### Network Outputs

| Output          | Description    |
| --------------- | -------------- |
| `network_id`    | VPC network ID |
| `subnetwork_id` | Subnetwork ID  |

### Database Outputs

| Output                            | Description                     |
| --------------------------------- | ------------------------------- |
| `cloud_sql_connection_name`       | Cloud SQL connection name       |
| `cloud_sql_instance_name`         | Cloud SQL instance name         |
| `cloud_sql_service_account_email` | Cloud SQL service account email |
| `cloud_sql_database_name`         | Cloud SQL database name         |
| `cloud_sql_database_username`     | Cloud SQL database username     |

### Keycloak Cluster Outputs

| Output                             | Description                                                    | Sensitive |
| ---------------------------------- | -------------------------------------------------------------- | --------- |
| `keycloak_cluster_name`            | GKE cluster name                                               | No        |
| `keycloak_cluster_endpoint`        | GKE cluster endpoint for Kubernetes provider configuration     | No        |
| `keycloak_cluster_access_token`    | Access token for Kubernetes provider configuration             | Yes       |
| `keycloak_cluster_ca_certificate`  | CA certificate for Kubernetes provider configuration           | No        |
| `keycloak_gcp_service_account_email` | Keycloak GCP service account email for Workload Identity       | No        |

### Ingress Outputs

| Output                       | Description                   |
| ---------------------------- | ----------------------------- |
| `keycloak_ingress_public_ip` | Keycloak Ingress public IP address |

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

### 4. Configure Providers (Root Module)

Create your root module configuration with provider setup. See the [Provider Configuration](#provider-configuration) section for detailed options.

**Recommended Approach:** Use the two-stage apply method:

**Create `providers.tf` in your root module:**
```hcl
provider "google" {
  project = var.project_id
  region  = var.project_region
}

provider "http" {
  # No configuration required
}

# Add these providers AFTER stage 1 completes
# provider "kubernetes" { ... }
# provider "kubectl" { ... }
# provider "postgresql" { ... }
```

**Create `main.tf` in your root module:**
```hcl
module "keycloak" {
  source = "./terraform-google-keycloak"

  project = var.project_id
  region  = var.project_region
  number  = var.project_number

  # Keycloak Configuration
  keycloak_image_project_id = var.project_id
  keycloak_image            = "us-central1-docker.pkg.dev/your-project/keycloak/keycloak:26.3.3"
  keycloak_crds_version     = "26.3.3"
  keycloak_operator_version = "26.3.3"
  managed_certificate_host  = "keycloak.example.com"

  # IMPORTANT: Disable Kubernetes resources for first apply
  deploy_k8s_grants    = false
  deploy_k8s_resources = false
}
```

### 5. Apply Stage 1 - Infrastructure

Initialize and apply to create VPC, Cloud SQL, and GKE cluster:

```bash
terraform init
terraform plan
terraform apply
```

This creates the infrastructure without any Kubernetes resources.

### 6. Configure Additional Providers

After stage 1 completes, add the Kubernetes, kubectl, and PostgreSQL providers to your `providers.tf`:

```hcl
data "google_secret_manager_secret_version_access" "keycloak_db_password" {
  secret  = "KEYCLOAK_DB_PASSWORD"
  project = var.project_id
}

provider "kubernetes" {
  host                   = "https://${module.keycloak.keycloak_cluster_endpoint}"
  token                  = module.keycloak.keycloak_cluster_access_token
  cluster_ca_certificate = base64decode(module.keycloak.keycloak_cluster_ca_certificate)
}

provider "kubectl" {
  host                   = "https://${module.keycloak.keycloak_cluster_endpoint}"
  token                  = module.keycloak.keycloak_cluster_access_token
  cluster_ca_certificate = base64decode(module.keycloak.keycloak_cluster_ca_certificate)
  load_config_file       = false
}

provider "postgresql" {
  scheme    = "gcppostgres"
  host      = module.keycloak.cloud_sql_connection_name
  username  = module.keycloak.cloud_sql_database_username
  password  = data.google_secret_manager_secret_version_access.keycloak_db_password.secret_data
  superuser = false
}
```

Update your module call in `main.tf` to enable Kubernetes resources:

```hcl
module "keycloak" {
  # ... same configuration as before ...

  # Enable Kubernetes resources for second apply
  deploy_k8s_grants    = true
  deploy_k8s_resources = true
}
```

### 7. Apply Stage 2 - Keycloak Application

Apply again to deploy Keycloak and all Kubernetes resources:

```bash
terraform apply
```

### 8. Configure DNS

After deployment, get the public IP address and configure your DNS:

```bash
terraform output keycloak_ingress_public_ip
```

Create an A record pointing your domain (e.g., `keycloak.example.com`) to the output IP address.

### 9. Wait for Certificate Provisioning

Google-managed certificates can take up to 15 minutes to provision. Monitor the certificate status:

```bash
kubectl get managedcertificate -n keycloak
```

Or connect to the cluster first:
```bash
gcloud container clusters get-credentials $(terraform output -raw keycloak_cluster_name) \
  --region=$(terraform output -raw region) \
  --project=$(terraform output -raw project)

kubectl get managedcertificate -n keycloak
```

## How It Works

### Module Architecture

This module is designed as a **comprehensive single-module deployment** with the following characteristics:

- **Requires external provider configuration**: The calling module must configure Kubernetes, kubectl, and PostgreSQL providers (see [Provider Configuration](#provider-configuration))
- **Two-stage deployment**: Due to provider circular dependencies, deployment requires two stages (infrastructure first, then application)
- **Automatic dependency management**: Once providers are configured, the module handles all resource dependencies automatically
- **Exported outputs**: Cluster connection details are exported as outputs for provider configuration and external resource creation
- **Internal data sources**: The module uses internal data sources to maintain consistency and provide connection information

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
   - Requires PostgreSQL provider configuration in calling module

3. **Kubernetes Layer**

   - Deploys a GKE Autopilot cluster for simplified operations
   - Creates a dedicated namespace for Keycloak resources
   - Installs Keycloak CRDs and the Keycloak Operator
   - Configures Workload Identity for secure GCP service account binding
   - Requires Kubernetes/kubectl provider configuration in calling module

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

### Provider Configuration Errors

**Error: Cannot reference module outputs in provider configuration**

This is expected due to the circular dependency. Use the two-stage apply approach:
1. First apply with `deploy_k8s_grants = false` and `deploy_k8s_resources = false`
2. Add provider configurations after infrastructure is created
3. Second apply with `deploy_k8s_grants = true` and `deploy_k8s_resources = true`

**Error: Failed to configure Kubernetes/kubectl provider**

Ensure:
- GKE cluster was created successfully in stage 1
- Module outputs are available: `terraform output keycloak_cluster_endpoint`
- You're using the correct output references in provider configuration
- The cluster API server is reachable

**Error: PostgreSQL provider cannot connect**

Ensure:
- Cloud SQL instance is created and running
- Secret Manager secret exists with the correct password
- Your local environment has Cloud SQL Proxy installed (for `gcppostgres` scheme)
- IAM authentication is enabled on the Cloud SQL instance

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
- Check that database grants were applied in stage 2

### Image Pull Errors

If the cluster cannot pull the Keycloak image:

- Verify the image path is correct
- Ensure the Compute Engine default service account has `roles/artifactregistry.reader`
- Check that the image exists in Artifact Registry
- Verify the image project ID is correctly configured

### Two-Stage Apply Issues

**Resources already exist error on stage 2:**
- This is normal - Terraform will update the state with the new configuration
- Run `terraform plan` to see what will change

**Kubernetes resources not deploying:**
- Verify you changed `deploy_k8s_grants` and `deploy_k8s_resources` to `true`
- Ensure all providers are configured in your root module
- Check that the cluster is accessible: `gcloud container clusters describe <cluster-name>`

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
