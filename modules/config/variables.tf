variable "config_file" {
  description = "Path to the service account YAML file. Mutually exclusive with config_yaml."
  type        = string
  default     = null
}

variable "config_yaml" {
  description = "Service account YAML passed as a string. Mutually exclusive with config_file."
  type        = string
  default     = null
}

variable "project_id" {
  description = "Fallback project for entries that do not resolve a project from the YAML."
  type        = string
  default     = null
}
