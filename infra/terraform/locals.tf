# Common naming and tagging conventions
locals {
  # Sanitized names (no dashes) for resources that don't allow them
  project_name_sanitized = replace(var.project_name, "-", "")

  # Common tags
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}
