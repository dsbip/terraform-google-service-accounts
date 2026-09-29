# Validation tests for ./modules/config. Each run feeds a broken YAML and
# asserts the EXACT list of error messages, so a new, missing or reworded
# message fails the test. Lists are compared via jsonencode() (list != tuple).

variables {
  config_file = null
  config_yaml = null
  project_id  = null

  # Shared fragments of expected messages.
  sa_keys_allowed = "account_id, create_ignore_already_exists, deletion_policy, description, disabled, display_name, folder_roles, iam_bindings, organization_roles, project_id, project_roles"
  account_id_rule = "must be 6-30 characters: a lowercase letter, then lowercase letters, digits or hyphens, not ending in a hyphen"
  role_rule       = "is not a valid role name (expected roles/NAME, projects/PROJECT/roles/NAME or organizations/ORG_ID/roles/NAME)"
  principal_rule  = "is not a supported principal (use user:, group:, serviceAccount:, domain:, principal://, principalSet:// or ref:<account_id>)"
  no_project      = "no project: set project_id on the service account or at the top of the file, or pass the module's project_id variable"
}

# --- Module input -----------------------------------------------------------------------

run "neither_config_file_nor_config_yaml" {
  command = plan
  module {
    source = "./modules/config"
  }

  assert {
    condition     = jsonencode(output.errors) == jsonencode(["module input: set config_file (path to a YAML file) or config_yaml"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "both_config_file_and_config_yaml" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_file = "tests/fixtures/complete.yaml"
    config_yaml = "service_accounts: []"
  }

  assert {
    condition     = jsonencode(output.errors) == jsonencode(["module input: set only one of config_file and config_yaml"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

# --- Top level ----------------------------------------------------------------------------

run "top_level_must_be_a_mapping" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = "- account_id: some-account\n"
  }

  assert {
    condition     = jsonencode(output.errors) == jsonencode(["(top level): the YAML must be a mapping with a service_accounts list"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "top_level_unknown_key_and_bad_project" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: Not_Valid
      service_account:          # typo: singular
        - account_id: typo-key
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "(top level): project_id \"Not_Valid\" is not a valid project ID",
      "(top level): unknown key \"service_account\" (allowed: project_id, service_accounts)",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "top_level_project_id_must_be_a_string" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = "project_id: [a-project, b-project]\nservice_accounts: []\n"
  }

  assert {
    condition     = jsonencode(output.errors) == jsonencode(["(top level): project_id must be a string"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "service_accounts_as_mapping_is_rejected" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      service_accounts:
        my-account:
          project_id: some-project
    EOT
  }

  assert {
    condition     = jsonencode(output.errors) == jsonencode(["service_accounts: must be a list; start each service account with \"- account_id: ...\""])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  assert {
    condition     = length(output.service_accounts) == 0
    error_message = "Nothing should be built from a malformed service_accounts"
  }
}

run "service_accounts_as_string_is_rejected" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = "service_accounts: my-account\n"
  }

  assert {
    condition     = jsonencode(output.errors) == jsonencode(["service_accounts: must be a list; start each service account with \"- account_id: ...\""])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

# --- Service account fields -----------------------------------------------------------------

run "service_account_items_must_be_mappings" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      service_accounts:
        - just-a-string
        - [a, list]
        -
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "service_accounts[0]: must be a mapping of service account fields (account_id, project_id, display_name, ...)",
      "service_accounts[1]: must be a mapping of service account fields (account_id, project_id, display_name, ...)",
      "service_accounts[2]: must be a mapping of service account fields (account_id, project_id, display_name, ...)",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "account_id_rules" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: good-project
      service_accounts:
        - account_id: Bad_ID
          displayname: typo
        - account_id: abc
        - account_id: ends-with-hyphen-
        - account_id: [not, a, string]
        - display_name: no account id
        - account_id: 1234567
        - account_id: a234567890123456789012345678901
        - account_id: ok-sixc
        - account_id: a23456789012345678901234567890
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "service_accounts[0] (Bad_ID): unknown key(s) \"displayname\" (allowed: ${var.sa_keys_allowed})",
      "service_accounts[0] (Bad_ID): account_id \"Bad_ID\" ${var.account_id_rule}",
      "service_accounts[1] (abc): account_id \"abc\" ${var.account_id_rule}",
      "service_accounts[2] (ends-with-hyphen-): account_id \"ends-with-hyphen-\" ${var.account_id_rule}",
      "service_accounts[3]: account_id must be a string",
      "service_accounts[4]: account_id is required",
      "service_accounts[5] (1234567): account_id \"1234567\" ${var.account_id_rule}",
      "service_accounts[6] (a234567890123456789012345678901): account_id \"a234567890123456789012345678901\" ${var.account_id_rule}",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  # Only the two valid accounts (6 and 30 characters) are handed on.
  assert {
    condition     = jsonencode(keys(output.service_accounts)) == jsonencode(["a23456789012345678901234567890", "ok-sixc"])
    error_message = "Got: ${jsonencode(keys(output.service_accounts))}"
  }
}

run "duplicate_account_ids" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: good-project
      service_accounts:
        - account_id: twice-defined
        - account_id: once-defined
        - account_id: twice-defined
          project_id: other-project
    EOT
  }

  assert {
    condition     = jsonencode(output.errors) == jsonencode(["service_accounts: account_id \"twice-defined\" is defined 2 times (service_accounts[0], service_accounts[2]); each account_id may appear only once per file"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "project_rules" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      service_accounts:
        - account_id: no-project-sa
        - account_id: bad-project-sa
          project_id: UPPER-case
        - account_id: list-project-sa
          project_id: [a-project]
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "service_accounts[0] (no-project-sa): ${var.no_project}",
      "service_accounts[1] (bad-project-sa): project_id \"UPPER-case\" is not a valid project ID",
      "service_accounts[2] (list-project-sa): project_id must be a string",
      "service_accounts[2] (list-project-sa): ${var.no_project}",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  assert {
    condition     = length(output.service_accounts) == 0
    error_message = "No account here is buildable"
  }
}

run "domain_scoped_projects_are_rejected" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: example.com:top-level
      service_accounts:
        - account_id: domain-scoped
          project_id: example.com:legacy-proj
          project_roles:
            - role: roles/viewer
              project_id: example.com:other
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "(top level): project_id \"example.com:top-level\" is not a valid project ID",
      "service_accounts[0] (domain-scoped): project_id \"example.com:legacy-proj\" is not a valid project ID",
      "service_accounts[0] (domain-scoped).project_roles[0]: project_id \"example.com:other\" is not a valid project ID",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  assert {
    condition     = length(output.service_accounts) == 0 && length(output.project_iam_members) == 0
    error_message = "Nothing domain-scoped may be handed on"
  }
}

run "scalar_field_rules" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: good-project
      service_accounts:
        - account_id: scalar-errors
          display_name: ${join("", [for i in range(101) : "x"])}
          description: ${join("", [for i in range(257) : "x"])}
          disabled: maybe
          create_ignore_already_exists: 3
          deletion_policy: delete
        - account_id: type-errors
          display_name: [a]
          description: {a: b}
        - account_id: at-the-limits
          display_name: ${join("", [for i in range(100) : "x"])}
          description: ${join("", [for i in range(256) : "x"])}
          deletion_policy: ABANDON
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "service_accounts[0] (scalar-errors): display_name is 101 UTF-8 bytes; the maximum is 100",
      "service_accounts[0] (scalar-errors): description is 257 UTF-8 bytes; the maximum is 256",
      "service_accounts[0] (scalar-errors): disabled must be true or false",
      "service_accounts[0] (scalar-errors): create_ignore_already_exists must be true or false",
      "service_accounts[0] (scalar-errors): deletion_policy \"delete\" must be one of DELETE, PREVENT, ABANDON",
      "service_accounts[1] (type-errors): display_name must be a string",
      "service_accounts[1] (type-errors): description must be a string",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

# GCP measures these limits in UTF-8 bytes: "é" is 2 bytes and "€" is 3.
run "text_limits_count_utf8_bytes_not_characters" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: good-project
      service_accounts:
        - account_id: multibyte-over
          display_name: ${join("", [for i in range(51) : "é"])}
          description: ${join("", [for i in range(86) : "€"])}
        - account_id: multibyte-limit
          display_name: ${join("", [for i in range(50) : "é"])}
          description: ${join("", [for i in range(85) : "€"])}
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "service_accounts[0] (multibyte-over): display_name is 102 UTF-8 bytes; the maximum is 100",
      "service_accounts[0] (multibyte-over): description is 258 UTF-8 bytes; the maximum is 256",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  assert {
    condition     = output.service_accounts["multibyte-limit"].display_name == join("", [for i in range(50) : "é"]) && output.service_accounts["multibyte-limit"].description == join("", [for i in range(85) : "€"])
    error_message = "Multi-byte text at the limit must pass through unchanged"
  }
}

run "role_lists_must_be_lists" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: good-project
      service_accounts:
        - account_id: list-errors
          iam_bindings: {role: roles/viewer}
          project_roles: roles/viewer
          folder_roles: 5
          organization_roles: {a: b}
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "service_accounts[0] (list-errors): iam_bindings must be a list",
      "service_accounts[0] (list-errors): project_roles must be a list",
      "service_accounts[0] (list-errors): folder_roles must be a list",
      "service_accounts[0] (list-errors): organization_roles must be a list",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

# --- iam_bindings ---------------------------------------------------------------------------

run "iam_binding_shape_rules" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: good-project
      service_accounts:
        - account_id: binding-errors
          iam_bindings:
            - roles/iam.serviceAccountUser
            - members: [user:a@example.com]
            - role: roles/iam.serviceAccountUser
            - role: roles/iam.serviceAccountUser
              members: user:a@example.com
            - role: roles/iam.serviceAccountUser
              members: []
            - role: roles/iam.serviceAccountUser
              member: [user:a@example.com]
              authoritative: maybe
            - role: iam.serviceAccountUser
              members: [user:a@example.com]
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "service_accounts[0] (binding-errors).iam_bindings[0]: must be a mapping with role and members",
      "service_accounts[0] (binding-errors).iam_bindings[1]: role is required",
      "service_accounts[0] (binding-errors).iam_bindings[2]: members is required (a list of principals)",
      "service_accounts[0] (binding-errors).iam_bindings[3]: members must be a list",
      "service_accounts[0] (binding-errors).iam_bindings[4]: members must not be empty",
      "service_accounts[0] (binding-errors).iam_bindings[5]: unknown key(s) \"member\" (allowed: authoritative, condition, members, role)",
      "service_accounts[0] (binding-errors).iam_bindings[5]: members is required (a list of principals)",
      "service_accounts[0] (binding-errors).iam_bindings[5]: authoritative must be true or false",
      "service_accounts[0] (binding-errors).iam_bindings[6]: role \"iam.serviceAccountUser\" ${var.role_rule}",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  assert {
    condition     = length(output.sa_iam_members) == 0 && length(output.sa_iam_bindings) == 0
    error_message = "Invalid bindings must not be handed on: ${jsonencode(keys(output.sa_iam_members))}"
  }
}

run "principal_rules" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: good-project
      service_accounts:
        - account_id: member-errors
          iam_bindings:
            - role: roles/iam.serviceAccountUser
              members:
                - alice@example.com
                - user:alice
                - "group:"
                - allUsers
                - allAuthenticatedUsers
                - ref:missing-sa
                - ""
                - [nested]
                - domain:localhost
                - principalSet://example.com/x
                - "serviceAccount:"
                - User:alice@example.com
                - user:valid@example.com
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "service_accounts[0] (member-errors).iam_bindings[0].members[0]: \"alice@example.com\" ${var.principal_rule}",
      "service_accounts[0] (member-errors).iam_bindings[0].members[1]: \"user:alice\" ${var.principal_rule}",
      "service_accounts[0] (member-errors).iam_bindings[0].members[2]: \"group:\" ${var.principal_rule}",
      "service_accounts[0] (member-errors).iam_bindings[0].members[3]: allUsers is not allowed; public principals must never be able to use a service account",
      "service_accounts[0] (member-errors).iam_bindings[0].members[4]: allAuthenticatedUsers is not allowed; public principals must never be able to use a service account",
      "service_accounts[0] (member-errors).iam_bindings[0].members[5]: \"ref:missing-sa\" does not match any account_id in this file",
      "service_accounts[0] (member-errors).iam_bindings[0].members[6]: must be a non-empty string",
      "service_accounts[0] (member-errors).iam_bindings[0].members[7]: must be a non-empty string",
      "service_accounts[0] (member-errors).iam_bindings[0].members[8]: \"domain:localhost\" ${var.principal_rule}",
      "service_accounts[0] (member-errors).iam_bindings[0].members[9]: \"principalSet://example.com/x\" ${var.principal_rule}",
      "service_accounts[0] (member-errors).iam_bindings[0].members[10]: \"serviceAccount:\" ${var.principal_rule}",
      "service_accounts[0] (member-errors).iam_bindings[0].members[11]: \"User:alice@example.com\" ${var.principal_rule}",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  # Only the one valid principal survives; nothing invalid or unresolved leaks out.
  assert {
    condition     = jsonencode(keys(output.sa_iam_members)) == jsonencode(["member-errors|roles/iam.serviceAccountUser|user:valid@example.com"])
    error_message = "Got: ${jsonencode(keys(output.sa_iam_members))}"
  }
}

run "ref_to_account_without_project_is_not_misreported" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      service_accounts:
        - account_id: target-sa
        - account_id: caller-sa
          project_id: good-project
          iam_bindings:
            - role: roles/iam.serviceAccountUser
              members: [ref:target-sa]
    EOT
  }

  # The ref names a defined account, so only the missing project is reported.
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["service_accounts[0] (target-sa): ${var.no_project}"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  assert {
    condition     = length(output.sa_iam_members) == 0
    error_message = "An unresolved ref: must not be handed on"
  }
}

run "ref_to_invalid_account_is_not_handed_on" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: good-project
      service_accounts:
        - account_id: Bad_ID
        - account_id: caller-sa
          iam_bindings:
            - role: roles/iam.serviceAccountUser
              members: [ref:Bad_ID, user:ok@example.com]
    EOT
  }

  # Only the broken account is reported; the ref to it is not a second error...
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["service_accounts[0] (Bad_ID): account_id \"Bad_ID\" ${var.account_id_rule}"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  # ...and no principal pointing at it reaches the provider.
  assert {
    condition     = jsonencode(keys(output.sa_iam_members)) == jsonencode(["caller-sa|roles/iam.serviceAccountUser|user:ok@example.com"])
    error_message = "Got: ${jsonencode(keys(output.sa_iam_members))}"
  }
}

# --- project_roles / folder_roles / organization_roles -----------------------------------------

run "grant_rules" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: good-project
      service_accounts:
        - account_id: grant-errors
          project_roles:
            - role: roles/viewer
              roles: [roles/editor]
            - project_id: other-project
            - roles: []
            - roles: roles/viewer
            - roles: [roles/viewer, "", viewer]
            - not-a-role
            - role: roles/viewer
              project_id: Bad_Project
            - role: roles/viewer
              project: typo-project
            - [roles/viewer]
          folder_roles:
            - role: roles/viewer
            - role: roles/viewer
              folder_id: folders/abc
            - role: roles/viewer
              org_id: "123"
              folder_id: "456"
          organization_roles:
            - role: roles/viewer
            - role: roles/viewer
              org_id: org-123
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "service_accounts[0] (grant-errors).project_roles[0]: set role or roles, not both",
      "service_accounts[0] (grant-errors).project_roles[1]: set role or roles",
      "service_accounts[0] (grant-errors).project_roles[2]: roles must not be empty",
      "service_accounts[0] (grant-errors).project_roles[3]: roles must be a list",
      "service_accounts[0] (grant-errors).project_roles[4]: roles must be non-empty strings",
      "service_accounts[0] (grant-errors).project_roles[4]: role \"viewer\" ${var.role_rule}",
      "service_accounts[0] (grant-errors).project_roles[5]: role \"not-a-role\" ${var.role_rule}",
      "service_accounts[0] (grant-errors).project_roles[6]: project_id \"Bad_Project\" is not a valid project ID",
      "service_accounts[0] (grant-errors).project_roles[7]: unknown key(s) \"project\" (allowed: condition, project_id, role, roles)",
      "service_accounts[0] (grant-errors).project_roles[8]: must be a role name or a mapping with role or roles",
      "service_accounts[0] (grant-errors).folder_roles[0]: folder_id is required",
      "service_accounts[0] (grant-errors).folder_roles[1]: folder_id \"folders/abc\" must be a numeric folder ID, optionally prefixed with folders/",
      "service_accounts[0] (grant-errors).folder_roles[2]: unknown key(s) \"org_id\" (allowed: condition, folder_id, role, roles)",
      "service_accounts[0] (grant-errors).organization_roles[0]: org_id is required",
      "service_accounts[0] (grant-errors).organization_roles[1]: org_id \"org-123\" must be a numeric organization ID, optionally prefixed with organizations/",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  # Grants with a missing or malformed target are never handed on.
  assert {
    condition     = length(output.organization_iam_members) == 0 && jsonencode(keys(output.folder_iam_members)) == jsonencode(["grant-errors|folders/456|roles/viewer"])
    error_message = "Got: ${jsonencode(keys(output.folder_iam_members))} ${jsonencode(keys(output.organization_iam_members))}"
  }
}

# --- Conditions -----------------------------------------------------------------------------------

run "condition_rules" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: good-project
      service_accounts:
        - account_id: condition-errors
          iam_bindings:
            - role: roles/iam.serviceAccountUser
              members: [user:a@example.com]
              condition: request.time < timestamp("2030-01-01T00:00:00Z")
            - role: roles/iam.serviceAccountTokenCreator
              members: [user:a@example.com]
              condition:
                expression: "true"
          project_roles:
            - role: roles/viewer
              condition:
                title: t
                expresion: "true"
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "service_accounts[0] (condition-errors).iam_bindings[0]: condition must be a mapping with title and expression",
      "service_accounts[0] (condition-errors).iam_bindings[1]: condition.title is required",
      "service_accounts[0] (condition-errors).project_roles[0]: unknown key(s) in condition: \"expresion\" (allowed: description, expression, title)",
      "service_accounts[0] (condition-errors).project_roles[0]: condition.expression is required",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

# --- Cross-entry conflicts --------------------------------------------------------------------------

run "conflict_rules" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: proj-conflicts
      service_accounts:
        - account_id: conflict-sa
          iam_bindings:
            - role: roles/iam.serviceAccountUser
              authoritative: true
              members: [user:a@example.com]
            - role: roles/iam.serviceAccountUser
              members: [user:b@example.com]
            - role: roles/iam.serviceAccountTokenCreator
              authoritative: true
              members: [user:a@example.com]
            - role: roles/iam.serviceAccountTokenCreator
              authoritative: true
              members: [user:c@example.com]
            - role: roles/iam.serviceAccountAdmin
              members: [user:a@example.com]
              condition: {title: t1, expression: "true"}
            - role: roles/iam.serviceAccountAdmin
              members: [user:a@example.com]
              condition: {title: t1, expression: "false"}
          project_roles:
            - role: roles/viewer
              condition: {title: t, expression: "a"}
            - role: roles/viewer
              condition: {title: t, expression: "b"}
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "service_accounts[0] (conflict-sa).iam_bindings[4], service_accounts[0] (conflict-sa).iam_bindings[5]: role roles/iam.serviceAccountAdmin for user:a@example.com is granted more than once under condition title \"t1\" with different condition contents; give each condition a unique title",
      "service_accounts[0] (conflict-sa).iam_bindings[2], service_accounts[0] (conflict-sa).iam_bindings[3]: role roles/iam.serviceAccountTokenCreator has more than one authoritative binding; merge their members into one entry",
      "service_accounts[0] (conflict-sa).project_roles[0], service_accounts[0] (conflict-sa).project_roles[1]: role roles/viewer on projects/proj-conflicts is granted more than once under condition title \"t\" with different condition contents; give each condition a unique title",
      "service account conflict-sa: role roles/iam.serviceAccountUser is granted both with authoritative: true and additively; an authoritative binding removes every member it does not list, so use one mode per role",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "authoritative_bindings_with_distinct_conditions_are_allowed" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: good-project
      service_accounts:
        - account_id: cond-bindings
          iam_bindings:
            - role: roles/iam.serviceAccountUser
              authoritative: true
              members: [group:day@example.com]
              condition: {title: day, expression: "request.time.getHours('UTC') < 12"}
            - role: roles/iam.serviceAccountUser
              authoritative: true
              members: [group:night@example.com]
              condition: {title: night, expression: "request.time.getHours('UTC') >= 12"}
    EOT
  }

  assert {
    condition     = length(output.errors) == 0
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  assert {
    condition     = jsonencode(keys(output.sa_iam_bindings)) == jsonencode(["cond-bindings|roles/iam.serviceAccountUser|day", "cond-bindings|roles/iam.serviceAccountUser|night"])
    error_message = "Got: ${jsonencode(keys(output.sa_iam_bindings))}"
  }
}

run "missing_condition_title_has_no_follow_on_conflict" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: good-project
      service_accounts:
        - account_id: title-missing
          iam_bindings:
            - role: roles/iam.serviceAccountKeyAdmin
              members: [user:a@example.com]
              condition: {expression: "true"}
            - role: roles/iam.serviceAccountKeyAdmin
              members: [user:a@example.com]
    EOT
  }

  assert {
    condition     = jsonencode(output.errors) == jsonencode(["service_accounts[0] (title-missing).iam_bindings[0]: condition.title is required"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "many_errors_are_reported_together_in_file_order" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: good-project
      extra: 1
      service_accounts:
        - account_id: first-bad
          disabled: maybe
          project_roles: [not-a-role]
        - account_id: second-bad
          iam_bindings:
            - role: roles/iam.serviceAccountUser
              members: [nobody]
    EOT
  }

  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "(top level): unknown key \"extra\" (allowed: project_id, service_accounts)",
      "service_accounts[0] (first-bad): disabled must be true or false",
      "service_accounts[0] (first-bad).project_roles[0]: role \"not-a-role\" ${var.role_rule}",
      "service_accounts[1] (second-bad).iam_bindings[0].members[0]: \"nobody\" ${var.principal_rule}",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}
