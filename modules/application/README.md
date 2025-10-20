# Application Module

This Terraform module deploys the Keycloak application layer on an existing GKE cluster with Cloud SQL backend. It manages Kubernetes resources, database grants, and ingress configuration.

## Overview

The application module is responsible for deploying all Kubernetes and application-level resources for Keycloak. This module depends on outputs from the infrastructure module and must be deployed after the infrastructure is ready.

## Resources Created

This module creates the following Kubernetes and database resources:

### Database Grants

- **PostgreSQL Grants**: Database connection grants for configured users
- **Read Access**: `pg_read_all_data` role for read-only users
- **Write Access**: `pg_write_all_data` role for read-write users
- **Keycloak Service Account Grants**: Database permissions for Keycloak GCP service account

### Kubernetes Namespace

- **Keycloak Namespace**: Dedicated namespace for Keycloak resources (default: `keycloak`)

### Service Accounts & Workload Identity

- **Kubernetes Service Account**: KSA with Workload Identity annotations
- **IAM Binding**: Connects KSA to GCP service account for Workload Identity

### Keycloak CRDs

- **Keycloak CRD**: Custom Resource Definition for Keycloak instances
- **KeycloakRealmImport CRD**: Custom Resource Definition for realm imports
- **Readiness Check**: Ensures CRDs are established before proceeding

### Keycloak Operator

- **Operator Deployment**: Keycloak Operator to manage Keycloak instances

### Keycloak Secrets

- **Bootstrap Admin Secret**: Initial admin credentials
- **Database Secret**: Database credentials (IAM-based authentication)

### Keycloak Instance

- **Keycloak Deployment**: Managed by Keycloak Operator with:
  - Cloud SQL Proxy init container for database connectivity
  - IAM authentication to Cloud SQL
  - Workload Identity integration
  - Health and metrics endpoints enabled
  - Configurable number of instances
  - Custom pod template with resource requests

### Ingress & SSL

- **FrontendConfig**: HTTP to HTTPS redirect and SSL policy
- **ManagedCertificate**: Google-managed SSL certificate
- **BackendConfig**: Custom health check configuration
- **Ingress**: HTTPS load balancer with SSL termination

## Required Providers

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

## Usage

### Basic Usage

```hcl
module "keycloak_application" {
  source = "./modules/application"

  # Project Configuration
  project = "my-gcp-project"
  region  = "us-central1"

  # Infrastructure outputs
  db_instance_name                      = module.keycloak_infrastructure.cloud_sql_instance_name
  db_name                               = module.keycloak_infrastructure.cloud_sql_database_name
  keycloak_google_service_account_name  = module.keycloak_infrastructure.keycloak_gcp_service_account_name
  keycloak_google_service_account_email = module.keycloak_infrastructure.keycloak_gcp_service_account_email

  # Keycloak Configuration
  keycloak_image            = "us-central1-docker.pkg.dev/my-gcp-project/keycloak/keycloak:26.4"
  keycloak_crds_version     = "23.3.3"
  keycloak_operator_version = "23.3.3"
  managed_certificate_host  = "keycloak.example.com"
}
```

### Production Usage

```hcl
module "keycloak_application" {
  source = "./modules/application"

  # Project Configuration
  project = "my-gcp-project"
  region  = "us-central1"

  # Infrastructure outputs
  db_instance_name                      = module.keycloak_infrastructure.cloud_sql_instance_name
  db_name                               = module.keycloak_infrastructure.cloud_sql_database_name
  keycloak_google_service_account_name  = module.keycloak_infrastructure.keycloak_gcp_service_account_name
  keycloak_google_service_account_email = module.keycloak_infrastructure.keycloak_gcp_service_account_email

  # Database Access
  db_read_users  = ["readonly@example.com", "analyst@example.com"]
  db_write_users = ["admin@example.com"]

  # Namespace Configuration
  keycloak_namespace_name = "keycloak-prod"

  # Service Account Configuration
  keycloak_k8s_service_account_name = "keycloak-prod-ksa"

  # Keycloak Configuration
  keycloak_image            = "us-central1-docker.pkg.dev/my-gcp-project/keycloak/keycloak:26.4"
  keycloak_crds_version     = "23.3.3"
  keycloak_operator_version = "23.3.3"

  # SSL & Ingress Configuration
  managed_certificate_host  = "auth.example.com"
  ssl_policy_name          = "keycloak-prod-ssl"
  frontend_config_name     = "keycloak-prod-frontend"
  managed_certificate_name = "keycloak-prod-cert"
  backend_config_name      = "keycloak-prod-backend"
  ingress_name             = "keycloak-prod-ingress"
  public_ip_address_name   = "keycloak-prod-ip"
}
```

## Variables

### Required Variables

| Variable                                | Type   | Description                                          |
| --------------------------------------- | ------ | ---------------------------------------------------- |
| `project`                               | string | GCP project ID                                       |
| `region`                                | string | GCP region                                           |
| `db_instance_name`                      | string | Cloud SQL instance name (from infrastructure module) |
| `keycloak_google_service_account_name`  | string | Full service account resource name                   |
| `keycloak_google_service_account_email` | string | Service account email                                |
| `keycloak_image`                        | string | Keycloak container image                             |
| `keycloak_crds_version`                 | string | Version of Keycloak Operator CRDs                    |
| `keycloak_operator_version`             | string | Version of Keycloak Operator                         |
| `managed_certificate_host`              | string | Domain name for SSL certificate                      |

### Database Configuration

| Variable         | Type        | Default      | Description                  |
| ---------------- | ----------- | ------------ | ---------------------------- |
| `db_name`        | string      | `"keycloak"` | Database name                |
| `db_read_users`  | set(string) | `[]`         | Users with read-only access  |
| `db_write_users` | set(string) | `[]`         | Users with read-write access |

### Namespace Configuration

| Variable                  | Type   | Default      | Description               |
| ------------------------- | ------ | ------------ | ------------------------- |
| `keycloak_namespace_name` | string | `"keycloak"` | Kubernetes namespace name |

### Service Account Configuration

| Variable                            | Type   | Default          | Description                     |
| ----------------------------------- | ------ | ---------------- | ------------------------------- |
| `keycloak_k8s_service_account_name` | string | `"keycloak-ksa"` | Kubernetes service account name |

### Keycloak Secrets Configuration

| Variable                               | Type   | Default                    | Description                 |
| -------------------------------------- | ------ | -------------------------- | --------------------------- |
| `keycloak_bootstrap_admin_secret_name` | string | `"bootstrap-admin-secret"` | Bootstrap admin secret name |
| `keycloak_db_secret_name`              | string | `"db-secret"`              | Database secret name        |

### Frontend & SSL Configuration

| Variable               | Type   | Default                      | Description                                        |
| ---------------------- | ------ | ---------------------------- | -------------------------------------------------- |
| `ssl_policy_name`      | string | `"keycloak-ssl-policy"`      | SSL policy name (must match infrastructure module) |
| `frontend_config_name` | string | `"keycloak-frontend-config"` | Frontend config name                               |

### Certificate Configuration

| Variable                   | Type   | Default                          | Description              |
| -------------------------- | ------ | -------------------------------- | ------------------------ |
| `managed_certificate_name` | string | `"keycloak-managed-certificate"` | Managed certificate name |

### Backend Configuration

| Variable              | Type   | Default                     | Description         |
| --------------------- | ------ | --------------------------- | ------------------- |
| `backend_config_name` | string | `"keycloak-backend-config"` | Backend config name |

### Ingress Configuration

| Variable                 | Type   | Default                | Description                                               |
| ------------------------ | ------ | ---------------------- | --------------------------------------------------------- |
| `public_ip_address_name` | string | `"keycloak-public-ip"` | Public IP address name (must match infrastructure module) |
| `ingress_name`           | string | `"keycloak-ingress"`   | Ingress resource name                                     |

## Outputs

This module currently has no outputs defined. All necessary information is available through `kubectl` commands once deployed.

## Provider Configuration

This module requires properly configured providers. Here's the recommended configuration:

```hcl
# Kubernetes provider
provider "kubernetes" {
  host                   = "https://${module.keycloak_infrastructure.keycloak_cluster_endpoint}"
  token                  = module.keycloak_infrastructure.keycloak_cluster_access_token
  cluster_ca_certificate = base64decode(module.keycloak_infrastructure.keycloak_cluster_ca_certificate)
}

# kubectl provider
provider "kubectl" {
  host                   = "https://${module.keycloak_infrastructure.keycloak_cluster_endpoint}"
  token                  = module.keycloak_infrastructure.keycloak_cluster_access_token
  cluster_ca_certificate = base64decode(module.keycloak_infrastructure.keycloak_cluster_ca_certificate)
  load_config_file       = false
}

# PostgreSQL provider
provider "postgresql" {
  scheme    = "gcppostgres"
  host      = module.keycloak_infrastructure.cloud_sql_connection_name
  username  = module.keycloak_infrastructure.cloud_sql_database_username
  password  = module.keycloak_infrastructure.cloud_sql_database_password
  superuser = false
}

# HTTP provider
provider "http" {
  # No configuration required
}
```

## Features

### Database Security

- **IAM Authentication**: Keycloak connects to Cloud SQL using IAM authentication
- **Cloud SQL Proxy**: Init container handles secure connection to database
- **No Passwords**: Database credentials use IAM service account authentication
- **Private Connectivity**: Database connection stays within private network

### High Availability

- **Scalable Instances**: Configure multiple Keycloak instances
- **Health Checks**: Custom health check on `/health/ready` endpoint
- **Automatic Failover**: GKE manages pod scheduling and recovery
- **Load Balancing**: HTTPS load balancer distributes traffic

### SSL & Security

- **Managed SSL Certificates**: Automatic provisioning and renewal
- **HTTPS Redirect**: All HTTP traffic redirected to HTTPS
- **Modern SSL Policy**: Configurable SSL policy (default: MODERN)
- **Workload Identity**: Secure service account authentication

### Monitoring & Operations

- **Health Endpoints**: `/health/ready` and `/health/live` endpoints
- **Metrics Enabled**: Prometheus metrics available
- **Structured Logs**: Cloud SQL Proxy uses structured logging
- **Kubernetes Events**: Standard Kubernetes event logging

## Dependencies

### Infrastructure Dependencies

This module requires the following from the infrastructure module:

1. **GKE Cluster**: Must be running and accessible
2. **Cloud SQL Instance**: Must be operational with IAM authentication enabled
3. **GCP Service Account**: Must have Cloud SQL Client role
4. **Public IP Address**: Static IP for ingress
5. **SSL Policy**: Must be created in infrastructure module

### Resource Dependencies

The module manages the following dependencies automatically:

1. Namespace created before all other resources
2. Service account created before Workload Identity binding
3. CRDs installed and established before operator
4. Operator running before Keycloak instance
5. Secrets created before Keycloak instance
6. Keycloak instance running before ingress configuration

## Important Notes

### Bootstrap Admin Credentials

The default admin credentials are:

- **Username**: `admin`
- **Password**: `admin`

**IMPORTANT**: Change these immediately after first login. The credentials are stored in a Kubernetes secret and should be rotated regularly in production.

### Database Authentication

The module uses IAM authentication for database access:

- No database passwords are required
- Cloud SQL Proxy handles authentication automatically
- The "dummy-password" in the database secret is never used

### Certificate Provisioning

Google-managed certificates can take up to 15 minutes to provision:

1. DNS must be configured before certificate provisioning
2. Create an A record pointing to the static IP
3. Monitor certificate status: `kubectl get managedcertificate -n keycloak`

### Cloud SQL Proxy

The Cloud SQL Proxy runs as an init container with:

- Private IP connectivity
- IAM authentication enabled
- Structured logging
- 2Gi memory and 1 CPU core allocated
- Runs as non-root for security

### Keycloak Operator

The operator is deployed from the official Keycloak GitHub repository:

- Version must match CRDs version
- Manages Keycloak instance lifecycle
- Handles rolling updates
- Creates Kubernetes service automatically

## Access Keycloak

After deployment:

1. **Get the public IP**:

   ```bash
   kubectl get ingress -n keycloak
   ```

2. **Configure DNS**:
   Create an A record pointing your domain to the public IP

3. **Wait for certificate**:

   ```bash
   kubectl get managedcertificate -n keycloak
   ```

4. **Access Keycloak**:
   Navigate to `https://your-domain.com`

5. **Login with admin credentials**:
   - Username: `admin`
   - Password: `admin` (change immediately!)

## Troubleshooting

### CRD Installation Issues

If CRDs fail to install:

- Check internet connectivity from cluster
- Verify CRDs version matches operator version
- Check cluster has permission to create CRDs

```bash
kubectl get crd | grep keycloak
```

### Operator Not Starting

If operator fails to start:

- Check operator logs: `kubectl logs -n keycloak deployment/keycloak-operator`
- Verify CRDs are established
- Check namespace exists and is active

### Keycloak Pod Not Starting

If Keycloak pods fail to start:

- **Check Cloud SQL Proxy logs**:
  ```bash
  kubectl logs -n keycloak <pod-name> -c cloud-sql-proxy
  ```
- **Check Keycloak logs**:
  ```bash
  kubectl logs -n keycloak <pod-name> -c keycloak
  ```
- **Verify Workload Identity**:
  - Check service account annotation
  - Verify IAM binding exists
  - Confirm service account has Cloud SQL Client role

### Database Connection Issues

If Keycloak cannot connect to database:

- Verify Cloud SQL instance is running
- Check IAM authentication is enabled
- Verify service account has proper roles
- Check database grants were applied successfully

### Certificate Not Provisioning

If managed certificate stays in "Provisioning":

- Verify DNS A record is correct
- Check domain is publicly resolvable: `dig your-domain.com`
- Ensure ingress is created and healthy
- Wait up to 15 minutes for initial provisioning
- Check certificate status:
  ```bash
  kubectl describe managedcertificate -n keycloak
  ```

### Ingress Issues

If ingress is not working:

- Verify backend service exists: `kubectl get svc -n keycloak`
- Check backend config: `kubectl get backendconfig -n keycloak`
- Verify frontend config exists
- Check ingress events: `kubectl describe ingress -n keycloak`

### Workload Identity Issues

If Workload Identity is not working:

- Verify annotation on Kubernetes service account
- Check IAM binding in GCP console
- Verify GCP service account has necessary roles
- Test from pod:
  ```bash
  kubectl run -it --rm test --image=google/cloud-sdk:alpine \
    --serviceaccount=keycloak-ksa --namespace=keycloak -- bash
  gcloud auth list
  ```

## Best Practices

1. **Security**:

   - Change default admin password immediately after deployment
   - Rotate admin credentials regularly
   - Use separate service accounts for different environments
   - Enable audit logging in Keycloak

2. **High Availability**:

   - Configure multiple Keycloak instances for production
   - Use REGIONAL database availability in infrastructure module
   - Monitor pod health and restart metrics
   - Configure appropriate resource requests/limits

3. **Monitoring**:

   - Enable metrics scraping
   - Set up alerts for pod failures
   - Monitor certificate expiration
   - Track database connection metrics

4. **Database Access**:

   - Grant minimal required permissions
   - Use read-only users for reporting
   - Keep write access restricted
   - Regularly audit database grants

5. **Updates**:
   - Test Keycloak updates in non-production first
   - Keep operator version in sync with CRDs
   - Monitor operator logs during updates
   - Have rollback plan ready

## Version Compatibility

This module is tested with:

- **Terraform**: >= 1.9.8
- **Keycloak Operator**: 23.3.3
- **Keycloak**: 26.4
- **Cloud SQL Proxy**: 2.14.1
- **GKE**: Autopilot clusters
- **PostgreSQL**: 17
