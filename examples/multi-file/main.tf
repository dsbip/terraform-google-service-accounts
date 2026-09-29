# One module instance per YAML file, e.g. one file per team or per system.
# Each file gets its own state addresses (module.service_accounts["<file>"]),
# and an account_id only has to be unique within its own file.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.33.0, < 9.0.0"
    }
  }
}

variable "config_dir" {
  description = "Directory holding the *.yaml files. Defaults to ../configs next to this example."
  type        = string
  default     = null
}

locals {
  config_dir   = coalesce(var.config_dir, "${path.module}/../configs")
  config_files = fileset(local.config_dir, "*.yaml")
}

# Every YAML file sets its own projects, so the provider needs no default project.
provider "google" {}

module "service_accounts" {
  source   = "../.."
  for_each = local.config_files

  config_file = "${local.config_dir}/${each.value}"
}

locals {
  emails_by_value   = { for e in flatten([for m in module.service_accounts : values(m.emails)]) : e => e... }
  duplicated_emails = [for e, copies in local.emails_by_value : e if length(copies) > 1]
}

output "emails" {
  description = "Service account emails keyed by file name, then account_id."
  value       = { for file, m in module.service_accounts : file => m.emails }

  # Two files defining the same account would both try to create it at apply
  # time; catch that at plan time instead.
  precondition {
    condition     = length(local.duplicated_emails) == 0
    error_message = "These service accounts are defined in more than one file: ${join(", ", local.duplicated_emails)}"
  }
}

output "service_accounts" {
  description = "Created service accounts keyed by file name, then account_id."
  value       = { for file, m in module.service_accounts : file => m.service_accounts }
}
