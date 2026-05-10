variable "subscription_id" {
  type        = string
  description = "The subscription ID where resources will be deployed."
}

variable "location" {
  type        = string
  default     = "East US 2"
  description = "The Azure region for the resources."
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment name (e.g., dev, prod)."
}

variable "project_name" {
  type        = string
  default     = "appliance-ai"
  description = "Project name prefix for resources."
}

variable "workiz_api_key" {
  type        = string
  sensitive   = true
  description = "Workiz API key for the nightly ticket sync function."
}

