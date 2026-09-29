# Unit tests for ./modules/config: YAML in, normalized maps out.
# The config module has no provider, so these runs need no credentials or mocks.
# Lists are compared via jsonencode() because list(string) != tuple in HCL.

variables {
  config_file = null
  config_yaml = null
  project_id  = null
}

# --- Full fixture ------------------------------------------------------------------

run "complete_fixture_has_no_errors" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_file = "tests/fixtures/complete.yaml"
  }

  assert {
    condition     = length(output.errors) == 0
    error_message = "Unexpected errors: ${jsonencode(output.errors)}"
  }
  assert {
    condition     = jsonencode(keys(output.service_accounts)) == jsonencode(["app-runtime", "break-glass", "ci-deployer", "minimal-sa"])
    error_message = "Wrong service accounts: ${jsonencode(keys(output.service_accounts))}"
  }
  assert {
    condition     = length(output.sa_iam_members) == 10
    error_message = "Expected 10 additive SA grants, got: ${jsonencode(keys(output.sa_iam_members))}"
  }
  assert {
    condition     = length(output.sa_iam_bindings) == 1
    error_message = "Expected 1 authoritative binding, got: ${jsonencode(keys(output.sa_iam_bindings))}"
  }
  assert {
    condition     = length(output.project_iam_members) == 7
    error_message = "Expected 7 project grants, got: ${jsonencode(keys(output.project_iam_members))}"
  }
  assert {
    condition     = length(output.folder_iam_members) == 3
    error_message = "Expected 3 folder grants, got: ${jsonencode(keys(output.folder_iam_members))}"
  }
  assert {
    condition     = length(output.organization_iam_members) == 3
    error_message = "Expected 3 organization grants, got: ${jsonencode(keys(output.organization_iam_members))}"
  }
}

run "complete_fixture_service_account_fields" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_file = "tests/fixtures/complete.yaml"
  }

  # Everything unset stays null, so the provider applies its own defaults.
  assert {
    condition = (
      output.service_accounts["minimal-sa"].project_id == "file-default-proj" &&
      output.service_accounts["minimal-sa"].display_name == null &&
      output.service_accounts["minimal-sa"].description == null &&
      output.service_accounts["minimal-sa"].disabled == null &&
      output.service_accounts["minimal-sa"].create_ignore_already_exists == null &&
      output.service_accounts["minimal-sa"].deletion_policy == null
    )
    error_message = "minimal-sa defaults are wrong: ${jsonencode(output.service_accounts["minimal-sa"])}"
  }
  assert {
    condition = (
      output.service_accounts["app-runtime"].project_id == "app-prod-proj" &&
      output.service_accounts["app-runtime"].display_name == "App runtime" &&
      output.service_accounts["app-runtime"].disabled == false &&
      output.service_accounts["app-runtime"].create_ignore_already_exists == true &&
      output.service_accounts["app-runtime"].deletion_policy == "PREVENT"
    )
    error_message = "app-runtime fields are wrong: ${jsonencode(output.service_accounts["app-runtime"])}"
  }
  assert {
    condition     = output.service_accounts["ci-deployer"].description == "Deploys the app from GitHub Actions"
    error_message = "ci-deployer description not passed through"
  }
  assert {
    condition     = output.service_accounts["break-glass"].disabled == true
    error_message = "break-glass should be disabled"
  }
  assert {
    condition     = output.service_accounts["app-runtime"].email == "app-runtime@app-prod-proj.iam.gserviceaccount.com"
    error_message = "Wrong email: ${output.service_accounts["app-runtime"].email}"
  }
  assert {
    condition     = output.service_accounts["app-runtime"].member == "serviceAccount:app-runtime@app-prod-proj.iam.gserviceaccount.com"
    error_message = "Wrong member: ${output.service_accounts["app-runtime"].member}"
  }
  assert {
    condition     = output.service_accounts["break-glass"].email == "break-glass@legacy-proj.iam.gserviceaccount.com"
    error_message = "Wrong email: ${output.service_accounts["break-glass"].email}"
  }
}

run "complete_fixture_principal_kinds" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_file = "tests/fixtures/complete.yaml"
  }

  # Every principal kind is accepted verbatim; ref: resolves to the SA email.
  assert {
    condition = alltrue([
      for m in [
        "user:alice@example.com",
        "group:platform-admins@example.com",
        "domain:example.com",
        "serviceAccount:external-bot@other-proj.iam.gserviceaccount.com",
        "serviceAccount:app-runtime@app-prod-proj.iam.gserviceaccount.com",
      ] : contains(keys(output.sa_iam_members), "ci-deployer|roles/iam.serviceAccountTokenCreator|${m}")
    ])
    error_message = "Missing token creator grants: ${jsonencode(keys(output.sa_iam_members))}"
  }
  assert {
    condition     = contains(keys(output.sa_iam_members), "ci-deployer|roles/iam.workloadIdentityUser|principalSet://iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/github/attribute.repository/acme/app")
    error_message = "principalSet:// member missing"
  }
  assert {
    condition     = contains(keys(output.sa_iam_members), "ci-deployer|roles/iam.workloadIdentityUser|principal://iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/github/subject/repo:acme/app:ref:refs/heads/main")
    error_message = "principal:// member missing"
  }
  # GKE Workload Identity members have no @ in them.
  assert {
    condition     = output.sa_iam_members["app-runtime|roles/iam.workloadIdentityUser|serviceAccount:app-prod-proj.svc.id.goog[default/app]"].sa_key == "app-runtime"
    error_message = "GKE workload identity member missing"
  }
  # No raw ref: values may leak through to resources.
  assert {
    condition     = alltrue([for g in output.sa_iam_members : !startswith(g.member, "ref:")])
    error_message = "Unresolved ref: in sa_iam_members"
  }
}

run "complete_fixture_conditions_and_authoritative" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_file = "tests/fixtures/complete.yaml"
  }

  assert {
    condition = jsonencode(output.sa_iam_members["app-runtime|roles/iam.serviceAccountTokenCreator|user:oncall@example.com|business-hours"].condition) == jsonencode({
      description = "Only during working hours"
      expression  = "request.time.getHours(\"Europe/Berlin\") >= 9 && request.time.getHours(\"Europe/Berlin\") <= 17"
      title       = "business-hours"
    })
    error_message = "Condition not carried through"
  }
  # Authoritative members: ref resolved, duplicates removed, sorted.
  assert {
    condition = jsonencode(output.sa_iam_bindings["app-runtime|roles/iam.serviceAccountUser"].members) == jsonencode([
      "group:sre@example.com",
      "serviceAccount:ci-deployer@file-default-proj.iam.gserviceaccount.com",
    ])
    error_message = "Wrong authoritative members: ${jsonencode(output.sa_iam_bindings["app-runtime|roles/iam.serviceAccountUser"].members)}"
  }
  assert {
    condition     = output.sa_iam_bindings["app-runtime|roles/iam.serviceAccountUser"].condition == null
    error_message = "Authoritative binding should have no condition"
  }
  # Authoritative roles never also appear as additive members.
  assert {
    condition     = length([for k, g in output.sa_iam_members : k if g.sa_key == "app-runtime" && g.role == "roles/iam.serviceAccountUser"]) == 0
    error_message = "Authoritative role leaked into additive grants"
  }
  # Identical duplicate conditional grants collapse into one resource.
  assert {
    condition     = length([for k, g in output.sa_iam_members : k if g.sa_key == "break-glass"]) == 1
    error_message = "Duplicate break-glass grants were not collapsed"
  }
}

run "complete_fixture_resource_grants" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_file = "tests/fixtures/complete.yaml"
  }

  # Shorthand strings and roles: lists expand; project defaults to the SA's project.
  assert {
    condition = jsonencode(sort([for k, g in output.project_iam_members : k if g.sa_key == "ci-deployer"])) == jsonencode([
      "ci-deployer|projects/file-default-proj|roles/logging.logWriter",
      "ci-deployer|projects/file-default-proj|roles/monitoring.metricWriter",
      "ci-deployer|projects/file-default-proj|roles/run.admin",
      "ci-deployer|projects/shared-artifacts|roles/artifactregistry.writer",
    ])
    error_message = "Wrong ci-deployer project grants: ${jsonencode([for k, g in output.project_iam_members : k if g.sa_key == "ci-deployer"])}"
  }
  assert {
    condition     = output.project_iam_members["ci-deployer|projects/shared-artifacts|roles/artifactregistry.writer"].member == "serviceAccount:ci-deployer@file-default-proj.iam.gserviceaccount.com"
    error_message = "Project grant member should be the SA itself"
  }
  # Same role twice with different condition titles = two separate grants.
  assert {
    condition = (
      output.project_iam_members["app-runtime|projects/app-prod-proj|roles/secretmanager.secretAccessor|app-secrets-only"].condition.title == "app-secrets-only" &&
      output.project_iam_members["app-runtime|projects/app-prod-proj|roles/secretmanager.secretAccessor|shared-secrets"].condition.title == "shared-secrets"
    )
    error_message = "Conditional project grants missing"
  }
  assert {
    condition     = length([for k, g in output.project_iam_members : k if g.sa_key == "break-glass"]) == 1
    error_message = "Duplicate shorthand roles were not collapsed"
  }
  # Folder IDs normalize to folders/ID, org IDs to the bare number.
  assert {
    condition     = jsonencode(sort(distinct([for g in output.folder_iam_members : g.folder]))) == jsonencode(["folders/111111111111", "folders/222222222222"])
    error_message = "Folder IDs not normalized: ${jsonencode([for g in output.folder_iam_members : g.folder])}"
  }
  assert {
    condition     = alltrue([for g in output.organization_iam_members : g.org_id == "333333333333"])
    error_message = "Org IDs not normalized: ${jsonencode([for g in output.organization_iam_members : g.org_id])}"
  }
  assert {
    condition     = contains(keys(output.organization_iam_members), "app-runtime|organizations/333333333333|organizations/333333333333/roles/customAuditor")
    error_message = "Custom org role / unquoted numeric org_id not handled"
  }
}

# --- Project resolution -----------------------------------------------------------

run "project_precedence_sa_over_file_over_variable" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    project_id  = "var-project"
    config_yaml = <<-EOT
      project_id: file-project
      service_accounts:
        - account_id: uses-file
        - account_id: uses-own
          project_id: own-project
          project_roles:
            - roles/viewer
            - role: roles/editor
              project_id: grant-project
    EOT
  }

  assert {
    condition     = output.service_accounts["uses-file"].project_id == "file-project"
    error_message = "Top-level project_id should beat the variable"
  }
  assert {
    condition     = output.service_accounts["uses-own"].project_id == "own-project"
    error_message = "SA project_id should beat the top-level project_id"
  }
  assert {
    condition     = jsonencode(sort(keys(output.project_iam_members))) == jsonencode(["uses-own|projects/grant-project|roles/editor", "uses-own|projects/own-project|roles/viewer"])
    error_message = "project_roles targets wrong: ${jsonencode(keys(output.project_iam_members))}"
  }
}

run "project_falls_back_to_variable" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    project_id  = "var-project"
    config_yaml = <<-EOT
      service_accounts:
        - account_id: uses-var
    EOT
  }

  assert {
    condition     = output.service_accounts["uses-var"].project_id == "var-project" && output.service_accounts["uses-var"].email == "uses-var@var-project.iam.gserviceaccount.com"
    error_message = "Variable project not used: ${jsonencode(output.service_accounts["uses-var"])}"
  }
  assert {
    condition     = length(output.errors) == 0
    error_message = "Unexpected errors: ${jsonencode(output.errors)}"
  }
}

# --- Empty and near-empty inputs ------------------------------------------------------

run "blank_yaml_is_empty_config" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = "  \n"
  }

  assert {
    condition     = length(output.service_accounts) == 0 && length(output.errors) == 0
    error_message = "Blank YAML should be a valid empty config: ${jsonencode(output.errors)}"
  }
}

run "comment_only_yaml_is_empty_config" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      # nothing managed yet
        # indented comment
    EOT
  }

  assert {
    condition     = length(output.service_accounts) == 0 && length(output.errors) == 0
    error_message = "Comment-only YAML should be a valid empty config: ${jsonencode(output.errors)}"
  }
}

run "document_marker_only_is_empty_config" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = "---\n"
  }

  assert {
    condition     = length(output.service_accounts) == 0 && length(output.errors) == 0
    error_message = "'---' should be a valid empty config: ${jsonencode(output.errors)}"
  }
}

run "empty_and_null_service_accounts" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = "project_id: some-project\nservice_accounts:\n"
  }

  assert {
    condition     = length(output.service_accounts) == 0 && length(output.errors) == 0
    error_message = "service_accounts: (null) should be valid: ${jsonencode(output.errors)}"
  }
}

run "empty_list_service_accounts" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = "service_accounts: []\n"
  }

  assert {
    condition     = length(output.service_accounts) == 0 && length(output.errors) == 0
    error_message = "service_accounts: [] should be valid: ${jsonencode(output.errors)}"
  }
}

run "empty_role_lists_are_allowed" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: some-project
      service_accounts:
        - account_id: no-grants
          iam_bindings: []
          project_roles:
          folder_roles: []
          organization_roles: []
    EOT
  }

  assert {
    condition     = length(output.errors) == 0 && length(output.sa_iam_members) + length(output.project_iam_members) + length(output.folder_iam_members) + length(output.organization_iam_members) == 0
    error_message = "Empty role lists should be valid and produce nothing: ${jsonencode(output.errors)}"
  }
}

# --- YAML typing quirks ----------------------------------------------------------------

run "yaml_scalars_are_coerced" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    # Unquoted numeric IDs, "true" strings and YAML 1.1 booleans (yes) are accepted.
    config_yaml = <<-EOT
      project_id: some-project
      service_accounts:
        - account_id: coerced
          disabled: "true"
          create_ignore_already_exists: yes
          folder_roles:
            - role: roles/viewer
              folder_id: 123456789012
          organization_roles:
            - role: roles/viewer
              org_id: 987654321098
    EOT
  }

  assert {
    condition     = length(output.errors) == 0
    error_message = "Unexpected errors: ${jsonencode(output.errors)}"
  }
  assert {
    condition     = output.service_accounts["coerced"].disabled == true && output.service_accounts["coerced"].create_ignore_already_exists == true
    error_message = "Booleans not coerced"
  }
  assert {
    condition     = contains(keys(output.folder_iam_members), "coerced|folders/123456789012|roles/viewer") && contains(keys(output.organization_iam_members), "coerced|organizations/987654321098|roles/viewer")
    error_message = "Numeric IDs lost precision: ${jsonencode(keys(output.folder_iam_members))} ${jsonencode(keys(output.organization_iam_members))}"
  }
}

run "self_reference_via_ref" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = <<-EOT
      project_id: some-project
      service_accounts:
        - account_id: self-ref
          iam_bindings:
            - role: roles/iam.serviceAccountTokenCreator
              members: [ref:self-ref]
    EOT
  }

  assert {
    condition     = contains(keys(output.sa_iam_members), "self-ref|roles/iam.serviceAccountTokenCreator|serviceAccount:self-ref@some-project.iam.gserviceaccount.com")
    error_message = "Self reference not resolved: ${jsonencode(keys(output.sa_iam_members))}"
  }
}

run "config_file_and_config_yaml_are_equivalent" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    config_yaml = file("tests/fixtures/complete.yaml")
  }

  assert {
    condition     = length(output.errors) == 0 && length(output.service_accounts) == 4 && length(output.sa_iam_members) == 10
    error_message = "config_yaml should parse exactly like config_file"
  }
  assert {
    condition     = output.source == "config_yaml"
    error_message = "source should name config_yaml"
  }
}
