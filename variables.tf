variable "config_file" {
  description = "Path to the YAML file defining the service accounts (schema: see CLAUDE.md). Relative paths resolve from the directory Terraform runs in, so callers normally pass \"$${path.module}/service_accounts.yaml\". Set exactly one of config_file and config_yaml."
  type        = string
  default     = null

  validation {
    condition     = var.config_file == null || try(fileexists(var.config_file), false)
    error_message = "config_file must be the path to an existing YAML file."
  }
}

variable "config_yaml" {
  description = "The same YAML passed as a string, e.g. templatefile(\"service_accounts.yaml.tftpl\", {...}). Set exactly one of config_file and config_yaml."
  type        = string
  default     = null
}

variable "project_id" {
  description = "Project used for service accounts and project_roles entries that do not set project_id in the YAML, when the YAML has no top-level project_id either."
  type        = string
  default     = null

  validation {
    condition     = var.project_id == null || can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 lowercase letters, digits or hyphens; domain-scoped IDs are not supported)."
  }
}
