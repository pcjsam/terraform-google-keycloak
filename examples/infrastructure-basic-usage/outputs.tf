output "network_id" {
  description = "VPC network ID"
  value       = module.keycloak_infrastructure.network_id
}

output "subnetwork_id" {
  description = "Subnetwork ID"
  value       = module.keycloak_infrastructure.subnetwork_id
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name for provider configuration"
  value       = module.keycloak_infrastructure.cloud_sql_connection_name
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name"
  value       = module.keycloak_infrastructure.cloud_sql_instance_name
}

output "cloud_sql_database_name" {
  description = "Cloud SQL database name"
  value       = module.keycloak_infrastructure.cloud_sql_database_name
}

output "cloud_sql_database_username" {
  description = "Cloud SQL database username"
  value       = module.keycloak_infrastructure.cloud_sql_database_username
}

output "keycloak_cluster_name" {
  description = "GKE cluster name"
  value       = module.keycloak_infrastructure.keycloak_cluster_name
}

output "keycloak_cluster_endpoint" {
  description = "GKE cluster endpoint for Kubernetes provider configuration"
  value       = module.keycloak_infrastructure.keycloak_cluster_endpoint
}

output "keycloak_gcp_service_account_email" {
  description = "Keycloak GCP service account email"
  value       = module.keycloak_infrastructure.keycloak_gcp_service_account_email
}

output "keycloak_ingress_public_ip" {
  description = "Static IP address for ingress configuration"
  value       = module.keycloak_infrastructure.keycloak_ingress_public_ip
}
