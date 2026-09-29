terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.33.0, < 9.0.0"
    }
  }
}

variable "project_id" {
  description = "Project the google provider bills API calls to. The YAML sets its own projects."
  type        = string
  default     = "acme-app-prod"
}

provider "google" {
  project = var.project_id
}

module "service_accounts" {
  source = "../.."

  config_file = "${path.module}/service_accounts.yaml"
}

output "emails" {
  description = "Service account emails keyed by account_id."
  value       = module.service_accounts.emails
}

output "members" {
  description = "IAM member strings keyed by account_id."
  value       = module.service_accounts.members
}
