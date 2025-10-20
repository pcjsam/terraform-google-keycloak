# Terraform Google Keycloak

This Terraform project deploys a production-ready Keycloak instance on Google Cloud Platform (GCP) using Google Kubernetes Engine (GKE) Autopilot with a Cloud SQL PostgreSQL database.

## Architecture Overview

This project is organized into two separate modules to provide flexibility in deployment:

1. **[Infrastructure Module](modules/infrastructure/)**: Creates the foundational GCP infrastructure including VPC, Cloud SQL database, GKE cluster, and GCP service accounts
2. **[Application Module](modules/application/)**: Deploys Keycloak application resources including Kubernetes configurations, database grants, and ingress setup

### Complete Architecture Components

- **VPC Network**: Custom VPC with private subnet for secure networking
- **Cloud SQL PostgreSQL**: Fully managed PostgreSQL database with private IP
- **GKE Autopilot Cluster**: Managed Kubernetes cluster for running Keycloak
- **Keycloak Deployment**: Keycloak instance deployed using the Keycloak Operator
- **Cloud SQL Proxy**: Init container for secure database connectivity with IAM authentication
- **Load Balancer & Ingress**: HTTPS ingress with Google-managed SSL certificates
- **Workload Identity**: Secure GCP service account binding to Kubernetes service accounts
- **IAM Roles**: Proper IAM bindings for database and Artifact Registry access

## Module Structure

This project uses a **two-module architecture** that separates infrastructure from application concerns:

### Infrastructure Module (`modules/infrastructure/`)

The infrastructure module handles all GCP infrastructure resources:

- VPC network and subnet configuration
- Cloud SQL PostgreSQL instance with private IP
- GKE Autopilot cluster
- GCP service account for Keycloak
- Database instance and user creation
- Public IP address for ingress
- IAM roles and permissions

**Providers Required**: `google`

See the [Infrastructure Module README](modules/infrastructure/README.md) for detailed documentation.

### Application Module (`modules/application/`)

The application module handles all Kubernetes and application-layer resources:

- Kubernetes namespace creation
- Kubernetes service account configuration
- Workload Identity binding
- PostgreSQL database grants
- Keycloak CRDs and Operator installation
- Keycloak instance deployment
- SSL certificates and frontend configuration
- Backend configuration
- Ingress resource

**Providers Required**: `google`, `kubernetes`, `kubectl`, `postgresql`, `http`

See the [Application Module README](modules/application/README.md) for detailed documentation.

## Prerequisites

Before using these modules, ensure you have:

1. A GCP project with billing enabled
2. Terraform >= 1.9.8 installed
3. The following GCP APIs enabled:
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

Your root module must configure the following Terraform providers:

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

**Note**: The infrastructure module only requires the `google` provider, while the application module requires all five providers.

## Provider Configuration

### Important: Circular Dependency Challenge

When deploying both modules together, there is a **circular dependency** between provider configuration and resource creation:

- The Kubernetes, kubectl, and PostgreSQL providers need connection information (cluster endpoint, database connection string)
- But these resources are created by the infrastructure module
- Terraform providers are configured **before** any resources are created

This means you **cannot** reference module outputs directly in provider configurations without special handling.

### Deployment Approach

The **two-module architecture solves this problem** by allowing you to deploy infrastructure and application separately. Here's how to handle the deployment:

#### Option 1: Two-Stage Apply with Separate Modules (Recommended)

**Stage 1:** Deploy infrastructure module only

```hcl
# main.tf in your root module
provider "google" {
  project = var.project_id
  region  = var.project_region
}

module "keycloak_infrastructure" {
  source = "./modules/infrastructure"

  # Project Configuration
  project = var.project_id
  region  = var.project_region
  number  = var.project_number

  # Keycloak Configuration
  keycloak_image_project_id = var.project_id
  keycloak_cluster_name     = "keycloak-cluster"

  # Database Configuration
  db_instance_name = "keycloak-instance"
  db_name          = "keycloak"

  # Optional: Database Access
  db_read_users  = ["user1@example.com"]
  db_write_users = ["user2@example.com"]

  # SSL Configuration
  ssl_policy_name = "keycloak-ssl-policy"
}
```

Apply stage 1:

```bash
terraform init
terraform apply
```

**Stage 2:** Add application module after infrastructure is ready

```hcl
# Add to main.tf after stage 1 completes

data "google_secret_manager_secret_version_access" "keycloak_db_password" {
  secret  = "KEYCLOAK_DB_PASSWORD"
  project = var.project_id
}

provider "kubernetes" {
  host                   = "https://${module.keycloak_infrastructure.keycloak_cluster_endpoint}"
  token                  = module.keycloak_infrastructure.keycloak_cluster_access_token
  cluster_ca_certificate = base64decode(module.keycloak_infrastructure.keycloak_cluster_ca_certificate)
}

provider "kubectl" {
  host                   = "https://${module.keycloak_infrastructure.keycloak_cluster_endpoint}"
  token                  = module.keycloak_infrastructure.keycloak_cluster_access_token
  cluster_ca_certificate = base64decode(module.keycloak_infrastructure.keycloak_cluster_ca_certificate)
  load_config_file       = false
}

provider "postgresql" {
  scheme    = "gcppostgres"
  host      = module.keycloak_infrastructure.cloud_sql_connection_name
  username  = module.keycloak_infrastructure.cloud_sql_database_username
  password  = data.google_secret_manager_secret_version_access.keycloak_db_password.secret_data
  superuser = false
}

provider "http" {
  # No configuration required
}

module "keycloak_application" {
  source = "./modules/application"

  # Project Configuration
  project = var.project_id
  region  = var.project_region

  # Infrastructure outputs
  db_instance_name                      = module.keycloak_infrastructure.cloud_sql_instance_name
  db_name                               = module.keycloak_infrastructure.cloud_sql_database_name
  keycloak_google_service_account_name  = "projects/${var.project_id}/serviceAccounts/${module.keycloak_infrastructure.keycloak_gcp_service_account_email}"
  keycloak_google_service_account_email = module.keycloak_infrastructure.keycloak_gcp_service_account_email

  # Keycloak Configuration
  keycloak_image            = "us-central1-docker.pkg.dev/your-project/keycloak/keycloak:26.4"
  keycloak_crds_version     = "26.3.3"
  keycloak_operator_version = "26.3.3"
  managed_certificate_host  = "keycloak.example.com"

  # Optional: Database Access
  db_read_users  = ["user1@example.com"]
  db_write_users = ["user2@example.com"]
}
```

Apply stage 2:

```bash
terraform apply
```

## Usage Examples

### Basic Usage

```hcl
# Infrastructure Module
module "keycloak_infrastructure" {
  source = "./modules/infrastructure"

  # Project Configuration
  project = "my-gcp-project"
  region  = "us-central1"
  number  = "123456789012"

  # Keycloak Configuration
  keycloak_image_project_id = "my-gcp-project"

  # Optional: Database Configuration
  db_tier              = "db-perf-optimized-N-2"
  db_edition           = "ENTERPRISE_PLUS"
  db_availability_type = "REGIONAL"
}

# Application Module (deploy after infrastructure)
module "keycloak_application" {
  source = "./modules/application"

  # Project Configuration
  project = "my-gcp-project"
  region  = "us-central1"

  # Infrastructure outputs
  db_instance_name                      = module.keycloak_infrastructure.cloud_sql_instance_name
  db_name                               = module.keycloak_infrastructure.cloud_sql_database_name
  keycloak_google_service_account_name  = "projects/my-gcp-project/serviceAccounts/${module.keycloak_infrastructure.keycloak_gcp_service_account_email}"
  keycloak_google_service_account_email = module.keycloak_infrastructure.keycloak_gcp_service_account_email

  # Keycloak Configuration
  keycloak_image            = "us-central1-docker.pkg.dev/my-gcp-project/keycloak/keycloak:26.4"
  keycloak_crds_version     = "26.3.3"
  keycloak_operator_version = "26.3.3"
  managed_certificate_host  = "keycloak.example.com"

  # Optional: Database Access
  db_read_users  = ["user1@example.com"]
  db_write_users = ["user2@example.com"]
}
```

For complete configuration examples and all available options, see:

- [Infrastructure Module README](modules/infrastructure/README.md)
- [Application Module README](modules/application/README.md)

## Module Variables and Outputs

For detailed information about variables and outputs for each module, please refer to:

- **Infrastructure Module**: See [modules/infrastructure/README.md](modules/infrastructure/README.md) for all infrastructure-related variables and outputs
- **Application Module**: See [modules/application/README.md](modules/application/README.md) for all application-related variables and outputs

## Deployment Steps

### 1. Enable Required APIs

First, ensure all required Google Cloud APIs are enabled in your GCP project.

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
docker build -t us-central1-docker.pkg.dev/your-project/keycloak/keycloak:26.4 .
docker push us-central1-docker.pkg.dev/your-project/keycloak/keycloak:26.4
```

### 4. Deploy Infrastructure Module

**Create `main.tf` in your root module:**

```hcl
provider "google" {
  project = var.project_id
  region  = var.project_region
}

module "keycloak_infrastructure" {
  source = "./modules/infrastructure"

  project = var.project_id
  region  = var.project_region
  number  = var.project_number

  keycloak_image_project_id = var.project_id
  managed_certificate_host  = "keycloak.example.com"
}
```

Initialize and apply to create VPC, Cloud SQL, and GKE cluster:

```bash
terraform init
terraform apply
```

### 5. Deploy Application Module

After infrastructure is ready, add the application module to your `main.tf`:

```hcl
data "google_secret_manager_secret_version_access" "keycloak_db_password" {
  secret  = "KEYCLOAK_DB_PASSWORD"
  project = var.project_id
}

provider "kubernetes" {
  host                   = "https://${module.keycloak_infrastructure.keycloak_cluster_endpoint}"
  token                  = module.keycloak_infrastructure.keycloak_cluster_access_token
  cluster_ca_certificate = base64decode(module.keycloak_infrastructure.keycloak_cluster_ca_certificate)
}

provider "kubectl" {
  host                   = "https://${module.keycloak_infrastructure.keycloak_cluster_endpoint}"
  token                  = module.keycloak_infrastructure.keycloak_cluster_access_token
  cluster_ca_certificate = base64decode(module.keycloak_infrastructure.keycloak_cluster_ca_certificate)
  load_config_file       = false
}

provider "postgresql" {
  scheme    = "gcppostgres"
  host      = module.keycloak_infrastructure.cloud_sql_connection_name
  username  = module.keycloak_infrastructure.cloud_sql_database_username
  password  = data.google_secret_manager_secret_version_access.keycloak_db_password.secret_data
  superuser = false
}

provider "http" {
  # No configuration required
}

module "keycloak_application" {
  source = "./modules/application"

  project = var.project_id
  region  = var.project_region

  db_instance_name                      = module.keycloak_infrastructure.cloud_sql_instance_name
  db_name                               = module.keycloak_infrastructure.cloud_sql_database_name
  keycloak_google_service_account_name  = "projects/${var.project_id}/serviceAccounts/${module.keycloak_infrastructure.keycloak_gcp_service_account_email}"
  keycloak_google_service_account_email = module.keycloak_infrastructure.keycloak_gcp_service_account_email

  keycloak_image            = "us-central1-docker.pkg.dev/your-project/keycloak/keycloak:26.4"
  keycloak_crds_version     = "26.3.3"
  keycloak_operator_version = "26.3.3"
  managed_certificate_host  = "keycloak.example.com"
}
```

Apply to deploy Keycloak and all Kubernetes resources:

```bash
terraform apply
```

### 6. Configure DNS

After deployment, get the public IP address and configure your DNS:

```bash
terraform output -raw keycloak_ingress_public_ip
```

Create an A record pointing your domain (e.g., `keycloak.example.com`) to the output IP address.

### 7. Wait for Certificate Provisioning

Google-managed certificates can take up to 15 minutes to provision. Monitor the certificate status:

```bash
gcloud container clusters get-credentials keycloak-cluster \
  --region=us-central1 \
  --project=your-project-id

kubectl get managedcertificate -n keycloak
```

## How It Works

### Module Architecture

This project uses a **two-module architecture** that separates concerns:

- **Infrastructure Module**: Handles all GCP infrastructure resources (VPC, Cloud SQL, GKE, service accounts)
- **Application Module**: Handles all Kubernetes and application resources (namespaces, deployments, ingress)
- **Two-stage deployment**: Infrastructure is deployed first, then application module references infrastructure outputs
- **Clean separation**: Each module has its own provider requirements and can be managed independently

### Architecture Components

1. **Networking Layer** (Infrastructure Module)

   - Creates a custom VPC network with a private subnet
   - Configures VPC peering for Cloud SQL private connectivity
   - Allocates a global static IP for the load balancer

2. **Database Layer** (Infrastructure Module)

   - Deploys a Cloud SQL PostgreSQL instance with private IP
   - Configures IAM authentication for secure, password-less connections
   - Sets up automated backups and point-in-time recovery
   - Creates default database and user

3. **Kubernetes Layer** (Infrastructure Module)

   - Deploys a GKE Autopilot cluster for simplified operations
   - Creates GCP service account for Keycloak with necessary IAM roles

4. **Database Grants** (Application Module)

   - Creates database grants for specified read/write users
   - Grants database permissions to Keycloak service account
   - Requires PostgreSQL provider configuration

5. **Keycloak Deployment** (Application Module)

   - Creates dedicated Kubernetes namespace
   - Configures Kubernetes service account with Workload Identity
   - Installs Keycloak CRDs and the Keycloak Operator
   - Deploys Keycloak instance with Cloud SQL Proxy init container
   - Configures health checks and metrics endpoints
   - Sets up bootstrap admin credentials via Kubernetes secrets

6. **Ingress & SSL** (Application Module)
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

### Module Deployment Errors

**Error: Cannot reference module outputs in provider configuration**

This is expected due to the circular dependency. Use the two-module approach:

1. Deploy infrastructure module first
2. Add provider configurations using infrastructure module outputs
3. Deploy application module second

**Error: Failed to configure Kubernetes/kubectl provider**

Ensure:

- Infrastructure module was deployed successfully
- GKE cluster is running and accessible
- Provider configuration uses correct infrastructure module outputs
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

### Module Integration Issues

**Resources already exist errors:**

- Ensure you're not duplicating resources between modules
- Check that infrastructure outputs are correctly passed to application module
- Run `terraform plan` to see what will change

**Application module failing to deploy:**

- Verify infrastructure module was deployed successfully
- Ensure all required providers are configured
- Check that all infrastructure outputs are correctly referenced
- Verify the GKE cluster is accessible

## Best Practices

1. **Enable Deletion Protection**: Set `db_deletion_protection = true` and `keycloak_cluster_deletion_protection = true` in production
2. **Use Regional Availability**: Configure `db_availability_type = "REGIONAL"` for high availability
3. **Regular Backups**: The module configures automated backups with 7-day transaction log retention
4. **Monitor Resources**: Enable Cloud Monitoring and Cloud Logging for visibility
5. **Security Scanning**: Regularly scan your Keycloak container images for vulnerabilities
6. **Rotate Credentials**: Periodically rotate the bootstrap admin password
7. **Use Private IPs**: Keep `public_ipv4_enabled = false` for enhanced security
8. **Version Pinning**: Pin provider and module versions for reproducible deployments

## Support

For issues and questions:

- Check the Troubleshooting section above
- Review Keycloak documentation: https://www.keycloak.org/documentation
- Review GKE Autopilot documentation: https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview
- Review Cloud SQL documentation: https://cloud.google.com/sql/docs
