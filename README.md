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

The **two-module architecture solves this problem** by allowing you to deploy infrastructure and application separately using targeted applies:

**Stage 1:** Deploy infrastructure module only

```bash
terraform init
terraform apply -target=module.keycloak_infrastructure
```

**Stage 2:** Deploy application module after infrastructure is ready

```bash
terraform apply
```

For a complete working example with all provider configurations and module setup, see the [Complete Example](examples/complete-example/).

## Usage Examples

For a complete working example that demonstrates deploying both modules together, see:

- [Complete Example](examples/complete-example/) - Full deployment with infrastructure and application modules

For individual module examples, see:

- [Infrastructure Module Examples](examples/) - Basic and production infrastructure configurations
- [Application Module Examples](examples/) - Basic and production application configurations

For detailed configuration options and all available variables, see:

- [Infrastructure Module README](modules/infrastructure/README.md)
- [Application Module README](modules/application/README.md)

## Module Variables and Outputs

For detailed information about variables and outputs for each module, please refer to:

- **Infrastructure Module**: See [modules/infrastructure/README.md](modules/infrastructure/README.md) for all infrastructure-related variables and outputs
- **Application Module**: See [modules/application/README.md](modules/application/README.md) for all application-related variables and outputs

## Deployment Steps

For a complete step-by-step deployment guide with working example code, see the [Complete Example](examples/complete-example/).

### Quick Start

1. **Enable Required APIs**: Ensure all required Google Cloud APIs are enabled in your GCP project

2. **Build and Push Keycloak Image**: Build and push your Keycloak image to Artifact Registry

3. **Deploy Infrastructure Module**: Deploy the infrastructure module first to create VPC, Cloud SQL, and GKE cluster

4. **Deploy Application Module**: After infrastructure is ready, deploy the application module to install Keycloak

5. **Configure DNS**: Point your domain to the ingress IP address

6. **Wait for Certificate**: Google-managed certificates can take up to 1 hour to provision

For detailed instructions, configuration options, and troubleshooting, see the [Complete Example](examples/complete-example/).

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
- Infrastructure module outputs the database password correctly
- Your local environment has Cloud SQL Proxy installed (for `gcppostgres` scheme)
- IAM authentication is enabled on the Cloud SQL instance
- PostgreSQL provider is configured with the infrastructure module's password output

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
- Ensure the PostgreSQL provider is configured with the infrastructure module's password output
- Verify the postgresql provider configuration is correct
- Verify IAM authentication is enabled on the Cloud SQL instance
- Check that database grants were applied in the application module deployment

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
