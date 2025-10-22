module "keycloak_infrastructure" {
  source = "github.com/pcjsam/terraform-google-keycloak//modules/infrastructure"

  # Project Configuration
  project = "my-gcp-project"
  region  = "us-central1"
  number  = "123456789012"

  # Keycloak Configuration
  keycloak_image_project_id = "my-gcp-project"
}
