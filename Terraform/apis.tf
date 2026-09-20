# GCP APIs this configuration needs enabled on the target project. A fresh
# or rarely used project (like a free tier account created just for this
# exercise) very likely does not have the Cloud Run Admin API enabled by
# default. Without this step, `terraform apply` fails on the very first
# run with a 403 "API not enabled" error, even though the caller is a
# Project Owner authenticated via Application Default Credentials.
# Enabling the APIs here means the whole deploy works from a single
# `terraform apply`, with no manual `gcloud services enable ...` step
# needed beforehand.
locals {
  required_apis = [
    # Cloud Run
    "run.googleapis.com",
    # Creating the dedicated service account
    "iam.googleapis.com",
    # Reading or checking project level resource state
    "cloudresourcemanager.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.required_apis)

  project = var.project_id
  service = each.value

  # Don't disable project wide APIs just because `terraform destroy` tears
  # down this one Cloud Run service. Something else in the project might
  # depend on them.
  disable_on_destroy = false
}
