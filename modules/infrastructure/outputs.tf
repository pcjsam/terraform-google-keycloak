/* 
** ******************************************************
** Networking - VPC and Subnet
** ******************************************************
*/

output "network_id" {
  description = "The ID of the VPC network"
  value       = google_compute_network.network.id
}

output "subnetwork_id" {
  description = "The ID of the subnetwork"
  value       = google_compute_subnetwork.subnetwork.id
}

/* 
** ******************************************************
** Database Instance
** ******************************************************
*/

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name"
  value       = google_sql_database_instance.postgresql_instance.connection_name
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.postgresql_instance.name
}

output "cloud_sql_service_account_email" {
  description = "Cloud SQL service account email"
  value       = google_sql_database_instance.postgresql_instance.service_account_email_address
}

/* 
** ******************************************************
** Database
** ******************************************************
*/

output "cloud_sql_database_name" {
  description = "Cloud SQL database name"
  value       = google_sql_database.postgresql_db.name
}

/* 
** ******************************************************
** Database - User
** ******************************************************
*/

output "cloud_sql_database_username" {
  description = "Cloud SQL user name"
  value       = google_sql_user.postgresql_user.name
}

output "cloud_sql_database_password" {
  description = "Cloud SQL user password"
  value       = google_sql_user.postgresql_user.password
  sensitive   = true
}

/* 
** ******************************************************
** Keycloak - Cluster
** ******************************************************
*/

output "keycloak_cluster_name" {
  description = "Keycloak GKE cluster name"
  value       = google_container_cluster.keycloak_cluster.name
}

output "keycloak_cluster_endpoint" {
  description = "Keycloak GKE cluster endpoint"
  value       = google_container_cluster.keycloak_cluster.endpoint
}

output "keycloak_cluster_access_token" {
  description = "Access token for Kubernetes provider configuration"
  value       = data.google_client_config.current.access_token
  sensitive   = true
}

output "keycloak_cluster_ca_certificate" {
  description = "CA certificate for Kubernetes provider configuration"
  value       = google_container_cluster.keycloak_cluster.master_auth[0].cluster_ca_certificate
}

/* 
** ******************************************************
** Keycloak - GCP Service Account
** ******************************************************
*/

output "keycloak_gcp_service_account_name" {
  description = "Keycloak GCP service account email"
  value       = google_service_account.keycloak_gsa.name
}

output "keycloak_gcp_service_account_email" {
  description = "Keycloak GCP service account email"
  value       = google_service_account.keycloak_gsa.email
}

/* 
** ******************************************************
** Keycloak - Ingress
** ******************************************************
*/

output "keycloak_ingress_public_ip" {
  description = "Keycloak Ingress public IP address"
  value       = google_compute_global_address.public_ip_address.address
}
