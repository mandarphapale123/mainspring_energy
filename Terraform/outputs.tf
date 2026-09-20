output "cloud_run_service_url" {
  description = "URL of the deployed Cloud Run service."
  value       = google_cloud_run_v2_service.mainspring_service.uri
}

output "cloud_run_service_name" {
  description = "Name of the deployed Cloud Run service."
  value       = google_cloud_run_v2_service.mainspring_service.name
}

output "cloud_run_service_account_email" {
  description = "Email of the dedicated service account running the Cloud Run service."
  value       = google_service_account.mainspring_sa.email
}
