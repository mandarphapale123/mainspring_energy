terraform {
  # Kept deliberately low so a real `terraform apply` can never fail on
  # version pinning alone. The test suite (Terraform/tests/) needs
  # Terraform >= 1.7 for mock_provider support, see the note at the top
  # of tests/main.tftest.hcl, but deploying the service does not.
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # No remote backend: Terraform state is kept locally (terraform.tfstate)
  # in this directory. Do not add a `backend` block here.
}

# No embedded credentials. The provider relies on whatever Application
# Default Credentials are active in the environment, e.g. via:
#   gcloud auth application-default login
provider "google" {
  project = var.project_id
  region  = var.region
}
