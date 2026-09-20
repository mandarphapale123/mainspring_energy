variable "project_id" {
  description = "GCP project ID to deploy the Cloud Run service into."
  type        = string
}

variable "region" {
  description = "GCP region to deploy the Cloud Run service into (e.g. \"us-central1\")."
  type        = string
}

variable "image" {
  description = "Full public container image URI to deploy to Cloud Run (e.g. \"docker.io/library/nginx:latest\" or \"us-docker.pkg.dev/project/repo/image:tag\")."
  type        = string
}

variable "invoker_members" {
  description = <<-EOT
    List of IAM members to grant roles/run.invoker on the Cloud Run service,
    e.g. ["user:someone@example.com"] or ["serviceAccount:sa@project.iam.gserviceaccount.com"].
    Defaults to an empty list: with no members supplied, nobody is granted
    invoker access via this resource (the service remains non-public; it is
    never granted to allUsers).
  EOT
  type    = list(string)
  default = []

  # Belt-and-suspenders enforcement of the "internal only" requirement: even
  # if someone passes allUsers/allAuthenticatedUsers by mistake at deploy
  # time, Terraform refuses to plan rather than silently making the service
  # public.
  validation {
    condition = (
      !contains(var.invoker_members, "allUsers") &&
      !contains(var.invoker_members, "allAuthenticatedUsers")
    )
    error_message = "invoker_members must not include \"allUsers\" or \"allAuthenticatedUsers\" — this service must not be made publicly invokable."
  }
}
