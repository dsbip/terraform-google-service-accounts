output "service_accounts" {
  description = "Normalized service accounts keyed by account_id (only fully valid ones)."
  value = {
    for k, s in local.buildable_service_accounts : k => {
      account_id                   = s.account_id
      project_id                   = s.project_id
      display_name                 = s.display_name
      description                  = s.description
      disabled                     = s.disabled
      create_ignore_already_exists = s.create_ignore_already_exists
      deletion_policy              = s.deletion_policy
      email                        = s.email
      member                       = s.email == null ? null : "serviceAccount:${s.email}"
    }
  }
}

output "sa_iam_members" {
  description = "Additive grants on the service accounts (google_service_account_iam_member), keyed by \"account_id|role|member[|condition title]\"."
  value       = local.sa_iam_members
}

output "sa_iam_bindings" {
  description = "Authoritative per-role grants on the service accounts (google_service_account_iam_binding), keyed by \"account_id|role[|condition title]\"."
  value       = local.sa_iam_bindings
}

output "project_iam_members" {
  description = "Roles granted to the service accounts on projects, keyed by \"account_id|projects/ID|role[|condition title]\"."
  value = {
    for k, g in local.resource_grants : k => {
      sa_key    = g.sa_key
      project   = g.target
      role      = g.role
      member    = g.member
      condition = g.condition
    } if g.kind == "project_roles"
  }
}

output "folder_iam_members" {
  description = "Roles granted to the service accounts on folders, keyed by \"account_id|folders/ID|role[|condition title]\"."
  value = {
    for k, g in local.resource_grants : k => {
      sa_key    = g.sa_key
      folder    = g.target
      role      = g.role
      member    = g.member
      condition = g.condition
    } if g.kind == "folder_roles"
  }
}

output "organization_iam_members" {
  description = "Roles granted to the service accounts on organizations, keyed by \"account_id|organizations/ID|role[|condition title]\"."
  value = {
    for k, g in local.resource_grants : k => {
      sa_key    = g.sa_key
      org_id    = g.target
      role      = g.role
      member    = g.member
      condition = g.condition
    } if g.kind == "organization_roles"
  }
}

output "errors" {
  description = "Every problem found in the YAML, as \"<path>: <message>\" strings. Empty when the config is valid."
  value       = local.errors
}

output "source" {
  description = "Human-readable name of the config source, for error messages."
  value       = var.config_yaml != null ? "config_yaml" : coalesce(var.config_file, "(no config)")
}
