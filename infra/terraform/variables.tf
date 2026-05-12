variable "subscription_id" {
  type        = string
  description = "The subscription ID where resources will be deployed."
}

variable "location" {
  type        = string
  default     = "East US 2"
  description = "The Azure region for the resources (agents, compute, storage)."
}

variable "search_location" {
  type        = string
  default     = "Sweden Central"
  description = "The Azure region for AI Search (can differ from primary region if primary is out of capacity)."
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

