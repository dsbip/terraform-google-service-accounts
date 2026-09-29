# Parsing and validation live in ./modules/config (no provider, no resources);
# this file only turns its normalized maps into resources.
module "config" {
  source = "./modules/config"

  config_file = var.config_file
  config_yaml = var.config_yaml
  project_id  = var.project_id
}

resource "google_service_account" "this" {
  for_each = module.config.service_accounts

  project                      = each.value.project_id
  account_id                   = each.value.account_id
  display_name                 = each.value.display_name
  description                  = each.value.description
  disabled                     = each.value.disabled
  create_ignore_already_exists = each.value.create_ignore_already_exists
  deletion_policy              = each.value.deletion_policy
}

# --- Principals granted roles ON the service accounts ------------------------------

# Additive: adds one member to a role, leaving other members of that role alone.
resource "google_service_account_iam_member" "this" {
  for_each = module.config.sa_iam_members

  service_account_id = google_service_account.this[each.value.sa_key].name
  role               = each.value.role
  member             = each.value.member

  dynamic "condition" {
    for_each = each.value.condition[*]
    content {
      title       = condition.value.title
      description = condition.value.description
      expression  = condition.value.expression
    }
  }
}

# Authoritative (authoritative: true): the listed members become the only
# members of the role on that service account.
resource "google_service_account_iam_binding" "this" {
  for_each = module.config.sa_iam_bindings

  service_account_id = google_service_account.this[each.value.sa_key].name
  role               = each.value.role
  members            = each.value.members

  dynamic "condition" {
    for_each = each.value.condition[*]
    content {
      title       = condition.value.title
      description = condition.value.description
      expression  = condition.value.expression
    }
  }
}

# --- Roles granted TO the service accounts on other resources --------------------
# Members are derived from the plan-time email, so depends_on (not a reference)
# is what orders these after the service accounts exist.

resource "google_project_iam_member" "this" {
  for_each = module.config.project_iam_members

  project = each.value.project
  role    = each.value.role
  member  = each.value.member

  dynamic "condition" {
    for_each = each.value.condition[*]
    content {
      title       = condition.value.title
      description = condition.value.description
      expression  = condition.value.expression
    }
  }

  depends_on = [google_service_account.this]
}

resource "google_folder_iam_member" "this" {
  for_each = module.config.folder_iam_members

  folder = each.value.folder
  role   = each.value.role
  member = each.value.member

  dynamic "condition" {
    for_each = each.value.condition[*]
    content {
      title       = condition.value.title
      description = condition.value.description
      expression  = condition.value.expression
    }
  }

  depends_on = [google_service_account.this]
}

resource "google_organization_iam_member" "this" {
  for_each = module.config.organization_iam_members

  org_id = each.value.org_id
  role   = each.value.role
  member = each.value.member

  dynamic "condition" {
    for_each = each.value.condition[*]
    content {
      title       = condition.value.title
      description = condition.value.description
      expression  = condition.value.expression
    }
  }

  depends_on = [google_service_account.this]
}
