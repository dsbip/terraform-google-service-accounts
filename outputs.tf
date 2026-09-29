output "service_accounts" {
  description = "Created service accounts keyed by account_id, with email, member, id, name, unique_id, project, display_name and disabled."
  value = {
    for k, sa in google_service_account.this : k => {
      account_id   = sa.account_id
      email        = sa.email
      member       = sa.member
      id           = sa.id
      name         = sa.name
      unique_id    = sa.unique_id
      project      = sa.project
      display_name = sa.display_name
      disabled     = sa.disabled
    }
  }

  # The validation gate: every YAML problem is reported here as one error, and
  # a failed precondition stops the plan before anything is created or changed.
  precondition {
    condition     = length(module.config.errors) == 0
    error_message = "Invalid service account configuration in ${module.config.source}:\n${join("\n", [for e in module.config.errors : "  - ${e}"])}"
  }
}

output "emails" {
  description = "Service account emails keyed by account_id. Known at plan time, so safe to use in for_each."
  value       = { for k, s in module.config.service_accounts : k => s.email }
  depends_on  = [google_service_account.this]
}

output "members" {
  description = "IAM member strings (serviceAccount:EMAIL) keyed by account_id. Known at plan time."
  value       = { for k, s in module.config.service_accounts : k => s.member }
  depends_on  = [google_service_account.this]
}
