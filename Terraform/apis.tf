# GCP APIs this configuration needs enabled on the target project. A fresh
# or rarely-used project (like a free-tier account created just for this
# exercise) very likely does NOT have the Cloud Run Admin API enabled by
# default — without this, `terraform apply` fails on the very first run
# with a 403 "API not enabled" error, even though the caller is a Project
# Owner authenticated via Application Default Credentials. Enabling the
# APIs here means the whole deploy works from a single `terraform apply`
# with no manual `gcloud services enable ...` step beforehand.
locals {
  required_apis = [
    "run.googleapis.com",               # Cloud Run
    "iam.googleapis.com",               # creating the dedicated service account
    "cloudresourcemanager.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.required_apis)

  project = var.project_id
  service = each.value

  # Don't disable project-wide APIs just because `terraform destroy` tears
  # down this one Cloud Run service — something else in the project may
  # depend on them.
  disable_on_destroy = false
}
