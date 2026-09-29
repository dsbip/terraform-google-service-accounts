# One YAML template, rendered per environment and passed in through config_yaml.
#   terraform plan -var environment=dev
#   terraform plan -var environment=prod

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.33.0, < 9.0.0"
    }
  }
}

variable "environment" {
  description = "Environment to render the service account template for."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

locals {
  project_ids = {
    dev     = "acme-web-dev"
    staging = "acme-web-staging"
    prod    = "acme-web-prod"
  }

  # Developers may deploy to dev by hand; other environments are CI-only.
  extra_deployers = var.environment == "dev" ? ["group:developers@acme.example.com"] : []
}

provider "google" {
  project = local.project_ids[var.environment]
}

module "service_accounts" {
  source = "../.."

  config_yaml = templatefile("${path.module}/service_accounts.yaml.tftpl", {
    env                 = var.environment
    project_id          = local.project_ids[var.environment]
    github_repo         = "acme/web"
    pool_project_number = "123456789012"
    oncall_group        = "oncall-${var.environment}@acme.example.com"
    extra_deployers     = local.extra_deployers
  })
}

output "emails" {
  description = "Service account emails keyed by account_id."
  value       = module.service_accounts.emails
}
