# Keycloak

## Overview

This repository contains the Dockerfile and build scripts for creating and deploying custom Keycloak container images to Google Cloud Artifact Registry.

## Requirements

- gcloud CLI
- kubectl
- Docker

## Dockerfile

The `Dockerfile` uses a multi-stage build process to create an optimized Keycloak container image:

- **Builder Stage**: Builds and optimizes the Keycloak configuration with the following features enabled:

  - Health checks (`KC_HEALTH_ENABLED=true`)
  - Metrics (`KC_METRICS_ENABLED=true`)
  - PostgreSQL database support (`KC_DB=postgres`)

- **Final Stage**: Creates a minimal production image with the pre-built, optimized Keycloak configuration

The Dockerfile accepts a `KEYCLOAK_VERSION` build argument to specify which Keycloak version to use from the official Quay.io registry.

## Building and Pushing Images

### Using the Build Script

The `build-and-push-image.sh` script automates the process of building and pushing Keycloak images to Google Cloud Artifact Registry.

#### Prerequisites

1. Authenticate with Google Cloud:

   ```bash
   gcloud auth login
   ```

2. Ensure you have the necessary IAM permissions:
   - `roles/iam.serviceAccountTokenCreator` (to impersonate the service account)
   - Access to the Artifact Registry repository

#### Environment Variables

Set the following environment variables before running the script:

```bash
export WORKLOAD_IDENTITY_PROVIDER='projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID'
export SERVICE_ACCOUNT='service-account@project-id.iam.gserviceaccount.com'
export REGION='us-central1'
export PROJECT_ID='my-gcp-project'
export APP='keycloak'
```

#### Usage

Run the script with the desired Keycloak version as an argument:

```bash
./build-and-push-image.sh <KEYCLOAK_VERSION>
```

**Example:**

```bash
./build-and-push-image.sh 23.0.0
```

This will:

1. Authenticate with Google Cloud using your credentials
2. Impersonate the specified service account to get an access token
3. Authenticate Docker with Google Artifact Registry
4. Build the Docker image with the specified Keycloak version
5. Push the image to Artifact Registry at: `${REGION}-docker.pkg.dev/${PROJECT_ID}/${APP}/${APP}:${KEYCLOAK_VERSION}`

#### Manual Build (Optional)

If you prefer to build and push manually:

```bash
# Authenticate Docker with Artifact Registry
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# Build the image
docker build --build-arg KEYCLOAK_VERSION=23.0.0 \
  -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/${APP}/${APP}:23.0.0 ./

# Push the image
docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/${APP}/${APP}:23.0.0
```

## Connect to Cluster locally

Get credentials with gcloud:

```bash
gcloud container clusters get-credentials <CLUSTER_NAME> -- location <CLUSTER_REGION> -- project <CLUSTER_PROJECT>
```
