# Dedicated service account for the Cloud Run service. Avoids using the
# default compute service account.
resource "google_service_account" "mainspring_sa" {
  project      = var.project_id
  account_id   = local.service_account_id
  display_name = local.service_account_display_name

  depends_on = [google_project_service.required]
}

# Cloud Run service running the supplied container image.
resource "google_cloud_run_v2_service" "mainspring_service" {
  name     = local.service_name
  project  = var.project_id
  location = var.region

  deletion_protection = false

  template {
    service_account = google_service_account.mainspring_sa.email

    containers {
      image = var.image

      ports {
        container_port = local.container_port
      }
    }
  }

  depends_on = [google_project_service.required]
}

# IAM restriction on who can invoke the service. No allUsers binding is
# created anywhere in this configuration, so the service is never publicly
# invokable. Each entry in var.invoker_members is granted roles/run.invoker
# individually; an empty list (the default) grants no invoker access at all.
resource "google_cloud_run_v2_service_iam_member" "invokers" {
  for_each = toset(var.invoker_members)

  project  = google_cloud_run_v2_service.mainspring_service.project
  location = google_cloud_run_v2_service.mainspring_service.location
  name     = google_cloud_run_v2_service.mainspring_service.name
  role     = "roles/run.invoker"
  member   = each.value
}
