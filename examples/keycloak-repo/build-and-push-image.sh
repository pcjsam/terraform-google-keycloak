#!/bin/bash

# Build and Push Keycloak Image
# Converts the image.yaml GitHub Actions workflow to a local bash script
#
# This script performs the same operations as the GitHub Actions workflow:
# 1. Authenticates with Google Cloud using Workload Identity Federation
# 2. Authenticates Docker with Google Artifact Registry
# 3. Builds and pushes a Keycloak Docker image
#
# Prerequisites:
# - gcloud CLI installed and configured
# - Docker installed and running
# - Appropriate GCP permissions for the authenticated user/service account

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# Configuration Variables
# ============================================================================
# To convert back to GitHub Actions, replace these with:
# - ${{ inputs.keycloak_version }}
# - ${{ vars.WORKLOAD_IDENTITY_PROVIDER }}
# - ${{ vars.SERVICE_ACCOUNT }}
# - ${{ vars.REGION }}
# - ${{ vars.PROJECT_ID }}
# - ${{ vars.APP }}

# Required: Keycloak version to build
# GitHub Actions equivalent: ${{ inputs.keycloak_version }}
KEYCLOAK_VERSION="${1:-}"

# Required: Google Cloud configuration
# GitHub Actions equivalent: ${{ vars.WORKLOAD_IDENTITY_PROVIDER }}
WORKLOAD_IDENTITY_PROVIDER="${WORKLOAD_IDENTITY_PROVIDER:-}"

# GitHub Actions equivalent: ${{ vars.SERVICE_ACCOUNT }}
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-}"

# GitHub Actions equivalent: ${{ vars.REGION }}
REGION="${REGION:-}"

# GitHub Actions equivalent: ${{ vars.PROJECT_ID }}
PROJECT_ID="${PROJECT_ID:-}"

# GitHub Actions equivalent: ${{ vars.APP }}
APP="${APP:-}"

# ============================================================================
# Input Validation
# ============================================================================

if [ -z "$KEYCLOAK_VERSION" ]; then
    echo "Error: KEYCLOAK_VERSION is required"
    echo "Usage: $0 <keycloak_version>"
    echo ""
    echo "Example: $0 23.0.0"
    echo ""
    echo "Or set environment variable: KEYCLOAK_VERSION=23.0.0 $0"
    exit 1
fi

if [ -z "$WORKLOAD_IDENTITY_PROVIDER" ]; then
    echo "Error: WORKLOAD_IDENTITY_PROVIDER environment variable is required"
    echo "Example: export WORKLOAD_IDENTITY_PROVIDER='projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID'"
    exit 1
fi

if [ -z "$SERVICE_ACCOUNT" ]; then
    echo "Error: SERVICE_ACCOUNT environment variable is required"
    echo "Example: export SERVICE_ACCOUNT='service-account@project-id.iam.gserviceaccount.com'"
    exit 1
fi

if [ -z "$REGION" ]; then
    echo "Error: REGION environment variable is required"
    echo "Example: export REGION='us-central1'"
    exit 1
fi

if [ -z "$PROJECT_ID" ]; then
    echo "Error: PROJECT_ID environment variable is required"
    echo "Example: export PROJECT_ID='my-gcp-project'"
    exit 1
fi

if [ -z "$APP" ]; then
    echo "Error: APP environment variable is required"
    echo "Example: export APP='keycloak'"
    exit 1
fi

echo "============================================================================"
echo "Build and Push Keycloak Image"
echo "============================================================================"
echo "Keycloak Version: $KEYCLOAK_VERSION"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "App: $APP"
echo "Service Account: $SERVICE_ACCOUNT"
echo "============================================================================"
echo ""

# ============================================================================
# Step 1: Checkout (equivalent to actions/checkout@v5)
# ============================================================================
# GitHub Actions equivalent:
#   - name: Checkout
#     uses: actions/checkout@v5
#
# Note: In local execution, we assume the script is run from the repository root
# or the appropriate directory. If running in CI/CD, you would cd to the repo.

echo "Step 1: Verifying repository location..."
if [ ! -f "Dockerfile" ]; then
    echo "Warning: Dockerfile not found in current directory"
    echo "Make sure you're running this script from the correct location"
    echo "Current directory: $(pwd)"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo "✓ Repository check complete"
echo ""

# ============================================================================
# Step 2: Google Authentication (equivalent to google-github-actions/auth@v3)
# ============================================================================
# GitHub Actions equivalent:
#   - name: Google Auth
#     id: auth
#     uses: google-github-actions/auth@v3
#     with:
#       token_format: access_token
#       workload_identity_provider: ${{ vars.WORKLOAD_IDENTITY_PROVIDER }}
#       service_account: ${{ vars.SERVICE_ACCOUNT }}
#
# The Google GitHub Actions auth action uses OIDC tokens in GitHub Actions.
# For local execution, we have two options:
# 1. Use Application Default Credentials (ADC) if already authenticated
# 2. Use a service account key file (less secure, for local dev only)
#
# This script will try to use the authenticated gcloud user or service account.

echo "Step 2: Authenticating with Google Cloud..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI is not installed"
    echo "Please install it from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    echo "Error: No active gcloud authentication found"
    echo "Please run: gcloud auth login"
    exit 1
fi

# Set the active project
echo "Setting active project to: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

# For Workload Identity Federation in local environment, we need to authenticate
# using the service account. In GitHub Actions, this is done automatically via OIDC.
# For local execution, we'll impersonate the service account or use ADC.

echo "Authenticating as service account: $SERVICE_ACCOUNT"
# Note: This requires the user to have iam.serviceAccountTokenCreator role
# Alternatively, if you have a service account key file, you can use:
# gcloud auth activate-service-account --key-file=path/to/key.json

# Get an access token for Docker authentication
# GitHub Actions equivalent: ${{ steps.auth.outputs.access_token }}
echo "Generating access token..."
ACCESS_TOKEN=$(gcloud auth print-access-token --impersonate-service-account="$SERVICE_ACCOUNT" 2>/dev/null || gcloud auth print-access-token)

if [ -z "$ACCESS_TOKEN" ]; then
    echo "Error: Failed to generate access token"
    exit 1
fi

echo "✓ Google Cloud authentication complete"
echo ""

# ============================================================================
# Step 3: Docker Authentication (equivalent to docker/login-action@v3)
# ============================================================================
# GitHub Actions equivalent:
#   - name: Docker Auth
#     id: docker-auth
#     uses: docker/login-action@v3
#     with:
#       username: oauth2accesstoken
#       password: ${{ steps.auth.outputs.access_token }}
#       registry: ${{ vars.REGION }}-docker.pkg.dev

echo "Step 3: Authenticating Docker with Artifact Registry..."

REGISTRY="${REGION}-docker.pkg.dev"
echo "Registry: $REGISTRY"

# Authenticate Docker using the access token
echo "$ACCESS_TOKEN" | docker login -u oauth2accesstoken --password-stdin "https://${REGISTRY}"

if [ $? -ne 0 ]; then
    echo "Error: Docker authentication failed"
    exit 1
fi

echo "✓ Docker authentication complete"
echo ""

# ============================================================================
# Step 4: Build and Push Container
# ============================================================================
# GitHub Actions equivalent:
#   - name: Build and Push Container
#     run: |-
#       docker build --build-arg KEYCLOAK_VERSION=${{ inputs.keycloak_version }} \
#         -t "${{ vars.REGION }}-docker.pkg.dev/${{ vars.PROJECT_ID }}/${{ vars.APP }}/${{ vars.APP }}:${{ inputs.keycloak_version }}" ./
#       docker push "${{ vars.REGION }}-docker.pkg.dev/${{ vars.PROJECT_ID }}/${{ vars.APP }}/${{ vars.APP }}:${{ inputs.keycloak_version }}"

echo "Step 4: Building and pushing Docker image..."

IMAGE_TAG="${REGISTRY}/${PROJECT_ID}/${APP}/${APP}:${KEYCLOAK_VERSION}"
echo "Image tag: $IMAGE_TAG"
echo ""

echo "Building Docker image..."
docker build \
    --build-arg KEYCLOAK_VERSION="$KEYCLOAK_VERSION" \
    -t "$IMAGE_TAG" \
    ./

if [ $? -ne 0 ]; then
    echo "Error: Docker build failed"
    exit 1
fi

echo "✓ Docker build complete"
echo ""

echo "Pushing Docker image to Artifact Registry..."
docker push "$IMAGE_TAG"

if [ $? -ne 0 ]; then
    echo "Error: Docker push failed"
    exit 1
fi

echo "✓ Docker push complete"
echo ""

# ============================================================================
# Success
# ============================================================================

echo "============================================================================"
echo "✓ SUCCESS: Image built and pushed successfully!"
echo "============================================================================"
echo "Image: $IMAGE_TAG"
echo "============================================================================"
echo ""

# ============================================================================
# HOW TO CONVERT THIS SCRIPT BACK TO GITHUB ACTIONS
# ============================================================================
#
# 1. Create a .github/workflows/build-image.yaml file
#
# 2. Replace the bash script variables with GitHub Actions syntax:
#    - KEYCLOAK_VERSION → ${{ inputs.keycloak_version }}
#    - WORKLOAD_IDENTITY_PROVIDER → ${{ vars.WORKLOAD_IDENTITY_PROVIDER }}
#    - SERVICE_ACCOUNT → ${{ vars.SERVICE_ACCOUNT }}
#    - REGION → ${{ vars.REGION }}
#    - PROJECT_ID → ${{ vars.PROJECT_ID }}
#    - APP → ${{ vars.APP }}
#
# 3. Use GitHub Actions for authentication instead of gcloud commands:
#    - Replace Step 2 with: uses: google-github-actions/auth@v3
#    - Replace Step 3 with: uses: docker/login-action@v3
#
# 4. Set up Workload Identity Federation:
#    - Configure the workload identity pool in GCP
#    - Configure GitHub as an identity provider
#    - Grant the service account the necessary permissions
#    - Set up repository secrets/variables for the configuration values
#
# 5. The workflow structure should follow:
#    name: Build and Push Keycloak Image
#    on:
#      workflow_dispatch:
#        inputs:
#          keycloak_version:
#            description: Keycloak version to build
#            required: true
#            type: string
#    jobs:
#      deploy:
#        permissions:
#          contents: read
#          id-token: write
#        runs-on: ubuntu-latest
#        steps:
#          - name: Checkout
#            uses: actions/checkout@v5
#          - name: Google Auth
#            [... rest of the workflow as in image.yaml ...]
#
# 6. GitHub Actions will automatically provide OIDC tokens for Workload Identity
#    Federation, which is more secure than using service account keys.
#
# ============================================================================
