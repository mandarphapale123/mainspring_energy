# Values that do not change between deployments live here as locals rather
# than as additional required variables, so that the only inputs Terraform
# needs are var.project_id, var.region, var.invoker_members and var.image.
locals {
  service_name                 = "mainspring-energy-service"
  service_account_id           = "mainspring-run-sa"
  service_account_display_name = "Cloud Run runtime SA for mainspring-energy-service"
  container_port               = 8080
}
