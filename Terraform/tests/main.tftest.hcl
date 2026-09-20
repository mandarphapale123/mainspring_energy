# Native Terraform tests (Terraform >= 1.7). Run with:
#   cd Terraform && terraform test
#
# mock_provider replaces the real google provider with a fake implementation
# built from its schema, so these tests need no GCP credentials, no network
# access to Google APIs, and never touch real infrastructure. They only
# exercise `command = plan`, checking the shape of what Terraform *would*
# create.
#
# NOTE: `terraform test` auto-loads terraform.tfvars from this directory
# just like `plan`/`apply` would, and a tfvars value beats a variable's own
# default. The variables block below pins every input explicitly (including
# invoker_members = []) so these tests stay hermetic regardless of whatever
# real values happen to be sitting in terraform.tfvars.

mock_provider "google" {}

variables {
  project_id      = "test-project"
  region          = "us-central1"
  image           = "docker.io/library/nginx:latest"
  invoker_members = []
}

# --- Dedicated service account -------------------------------------------

run "creates_dedicated_service_account" {
  command = plan

  assert {
    condition     = google_service_account.mainspring_sa.account_id == "mainspring-run-sa"
    error_message = "Expected a dedicated, named service account (not the default compute SA)."
  }
}

# --- Invoker access defaults to nobody ------------------------------------

run "default_invoker_members_grants_no_access" {
  command = plan
  # invoker_members not overridden here -> uses the [] pinned in the file's
  # variables block above (not terraform.tfvars's real-world value).

  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invokers) == 0
    error_message = "With invoker_members left at its default, no invoker IAM bindings should be created."
  }
}

# --- Invoker access is granted per supplied member ------------------------

run "grants_invoker_to_each_supplied_member" {
  command = plan

  variables {
    invoker_members = [
      "user:someone@example.com",
      "serviceAccount:caller@test-project.iam.gserviceaccount.com",
    ]
  }

  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invokers) == 2
    error_message = "Expected exactly one roles/run.invoker binding per entry in invoker_members."
  }

  assert {
    condition = alltrue([
      for binding in google_cloud_run_v2_service_iam_member.invokers : binding.role == "roles/run.invoker"
    ])
    error_message = "Every invoker binding must grant roles/run.invoker."
  }

  assert {
    condition = contains(
      [for binding in google_cloud_run_v2_service_iam_member.invokers : binding.member],
      "user:someone@example.com"
    )
    error_message = "Expected user:someone@example.com to be granted invoker access."
  }
}

# --- allUsers / allAuthenticatedUsers are rejected outright ---------------

run "rejects_allUsers_as_invoker" {
  command = plan

  variables {
    invoker_members = ["allUsers"]
  }

  expect_failures = [
    var.invoker_members,
  ]
}

run "rejects_allAuthenticatedUsers_as_invoker" {
  command = plan

  variables {
    invoker_members = ["allAuthenticatedUsers"]
  }

  expect_failures = [
    var.invoker_members,
  ]
}

# --- The service runs exactly the supplied image --------------------------

run "service_runs_supplied_image" {
  command = plan

  variables {
    image = "docker.io/example/mainspring:v1"
  }

  assert {
    # google_cloud_run_v2_service_iam_member represents `template` as a
    # repeated block (a list of objects) in this provider version, so it
    # must be indexed numerically rather than accessed as a single object.
    condition     = google_cloud_run_v2_service.mainspring_service.template[0].containers[0].image == "docker.io/example/mainspring:v1"
    error_message = "Cloud Run container image did not match var.image."
  }
}
