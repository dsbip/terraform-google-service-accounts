# Tests for the root module: YAML -> google_* resources, with the Google
# provider mocked (no credentials, nothing is created in GCP).
#
# With a mocked provider, computed attributes (email, name, unique_id, ...) are
# unknown at plan and random after apply, so assertions check the arguments the
# module sets, plus the plan-time emails/members outputs derived from the YAML.

mock_provider "google" {
  # The provider still validates arguments under mocks, and service_account_id
  # must look like a real service account name, so give computed attributes a
  # realistic shape instead of the random strings mocks generate by default.
  mock_resource "google_service_account" {
    defaults = {
      name   = "projects/mock-project/serviceAccounts/mock-account@mock-project.iam.gserviceaccount.com"
      email  = "mock-account@mock-project.iam.gserviceaccount.com"
      member = "serviceAccount:mock-account@mock-project.iam.gserviceaccount.com"
    }
  }
}

variables {
  config_file = "tests/fixtures/complete.yaml"
  config_yaml = null
  project_id  = null
}

# --- Plan: every resource type with the right arguments ------------------------------------

run "plan_creates_expected_resource_counts" {
  command = plan

  assert {
    condition     = length(google_service_account.this) == 4
    error_message = "Expected 4 service accounts, got ${length(google_service_account.this)}"
  }
  assert {
    condition     = length(google_service_account_iam_member.this) == 10
    error_message = "Expected 10 additive SA grants, got ${length(google_service_account_iam_member.this)}"
  }
  assert {
    condition     = length(google_service_account_iam_binding.this) == 1
    error_message = "Expected 1 authoritative SA binding, got ${length(google_service_account_iam_binding.this)}"
  }
  assert {
    condition     = length(google_project_iam_member.this) == 7
    error_message = "Expected 7 project grants, got ${length(google_project_iam_member.this)}"
  }
  assert {
    condition     = length(google_folder_iam_member.this) == 3
    error_message = "Expected 3 folder grants, got ${length(google_folder_iam_member.this)}"
  }
  assert {
    condition     = length(google_organization_iam_member.this) == 3
    error_message = "Expected 3 organization grants, got ${length(google_organization_iam_member.this)}"
  }
}

run "plan_service_account_arguments" {
  command = plan

  assert {
    condition = (
      google_service_account.this["app-runtime"].project == "app-prod-proj" &&
      google_service_account.this["app-runtime"].account_id == "app-runtime" &&
      google_service_account.this["app-runtime"].display_name == "App runtime" &&
      google_service_account.this["app-runtime"].disabled == false &&
      google_service_account.this["app-runtime"].create_ignore_already_exists == true &&
      google_service_account.this["app-runtime"].deletion_policy == "PREVENT"
    )
    error_message = "app-runtime arguments are wrong"
  }
  assert {
    condition     = google_service_account.this["ci-deployer"].description == "Deploys the app from GitHub Actions" && google_service_account.this["ci-deployer"].project == "file-default-proj"
    error_message = "ci-deployer arguments are wrong"
  }
  assert {
    condition     = google_service_account.this["break-glass"].disabled == true && google_service_account.this["break-glass"].project == "legacy-proj"
    error_message = "break-glass arguments are wrong"
  }
  # Unset optional fields are passed as null, leaving defaults to the provider.
  assert {
    condition     = google_service_account.this["minimal-sa"].display_name == null && google_service_account.this["minimal-sa"].description == null
    error_message = "minimal-sa should not set display_name/description"
  }
}

run "plan_service_account_iam" {
  command = plan

  assert {
    condition = (
      google_service_account_iam_member.this["ci-deployer|roles/iam.serviceAccountTokenCreator|group:platform-admins@example.com"].role == "roles/iam.serviceAccountTokenCreator" &&
      google_service_account_iam_member.this["ci-deployer|roles/iam.serviceAccountTokenCreator|group:platform-admins@example.com"].member == "group:platform-admins@example.com" &&
      length(google_service_account_iam_member.this["ci-deployer|roles/iam.serviceAccountTokenCreator|group:platform-admins@example.com"].condition) == 0
    )
    error_message = "Unconditional SA grant is wrong"
  }
  assert {
    condition = (
      google_service_account_iam_member.this["app-runtime|roles/iam.serviceAccountTokenCreator|user:oncall@example.com|business-hours"].condition[0].title == "business-hours" &&
      google_service_account_iam_member.this["app-runtime|roles/iam.serviceAccountTokenCreator|user:oncall@example.com|business-hours"].condition[0].description == "Only during working hours" &&
      startswith(google_service_account_iam_member.this["app-runtime|roles/iam.serviceAccountTokenCreator|user:oncall@example.com|business-hours"].condition[0].expression, "request.time.getHours")
    )
    error_message = "Conditional SA grant is wrong"
  }
  # ref:app-runtime resolves to the real email.
  assert {
    condition     = google_service_account_iam_member.this["ci-deployer|roles/iam.serviceAccountTokenCreator|serviceAccount:app-runtime@app-prod-proj.iam.gserviceaccount.com"].member == "serviceAccount:app-runtime@app-prod-proj.iam.gserviceaccount.com"
    error_message = "ref: member not resolved"
  }
  assert {
    condition = jsonencode(sort(tolist(google_service_account_iam_binding.this["app-runtime|roles/iam.serviceAccountUser"].members))) == jsonencode([
      "group:sre@example.com",
      "serviceAccount:ci-deployer@file-default-proj.iam.gserviceaccount.com",
    ])
    error_message = "Authoritative binding members are wrong"
  }
  assert {
    condition     = length(google_service_account_iam_binding.this["app-runtime|roles/iam.serviceAccountUser"].condition) == 0
    error_message = "Authoritative binding should have no condition block"
  }
}

run "plan_resource_grants" {
  command = plan

  assert {
    condition = (
      google_project_iam_member.this["ci-deployer|projects/shared-artifacts|roles/artifactregistry.writer"].project == "shared-artifacts" &&
      google_project_iam_member.this["ci-deployer|projects/shared-artifacts|roles/artifactregistry.writer"].member == "serviceAccount:ci-deployer@file-default-proj.iam.gserviceaccount.com"
    )
    error_message = "Cross-project grant is wrong"
  }
  assert {
    condition     = google_project_iam_member.this["app-runtime|projects/app-prod-proj|roles/secretmanager.secretAccessor|shared-secrets"].condition[0].title == "shared-secrets"
    error_message = "Conditional project grant is wrong"
  }
  assert {
    condition     = google_project_iam_member.this["break-glass|projects/legacy-proj|roles/viewer"].member == "serviceAccount:break-glass@legacy-proj.iam.gserviceaccount.com"
    error_message = "break-glass project grant is wrong"
  }
  assert {
    condition     = google_folder_iam_member.this["app-runtime|folders/222222222222|roles/logging.viewer"].folder == "folders/222222222222"
    error_message = "Folder grant is wrong"
  }
  assert {
    condition     = google_organization_iam_member.this["app-runtime|organizations/333333333333|roles/iam.securityReviewer"].org_id == "333333333333"
    error_message = "Organization grant is wrong"
  }
}

run "plan_outputs_are_known_at_plan_time" {
  command = plan

  assert {
    condition     = output.emails["ci-deployer"] == "ci-deployer@file-default-proj.iam.gserviceaccount.com"
    error_message = "emails output wrong: ${jsonencode(output.emails)}"
  }
  assert {
    condition     = output.members["break-glass"] == "serviceAccount:break-glass@legacy-proj.iam.gserviceaccount.com"
    error_message = "members output wrong: ${jsonencode(output.members)}"
  }
}

# --- Inputs ------------------------------------------------------------------------------------

run "config_yaml_input" {
  command = plan

  variables {
    config_file = null
    project_id  = "var-project"
    config_yaml = <<-EOT
      service_accounts:
        - account_id: inline-sa
          project_roles: [roles/viewer]
    EOT
  }

  assert {
    condition     = google_service_account.this["inline-sa"].project == "var-project" && length(google_project_iam_member.this) == 1
    error_message = "config_yaml / project_id variable not honoured"
  }
}

run "example_yaml_is_valid" {
  command = plan

  variables {
    config_file = "examples/complete/service_accounts.yaml"
  }

  assert {
    condition     = jsonencode(keys(google_service_account.this)) == jsonencode(["app-runtime", "break-glass-admin", "ci-deployer", "data-exporter"])
    error_message = "Example accounts: ${jsonencode(keys(google_service_account.this))}"
  }
  assert {
    condition     = google_service_account.this["data-exporter"].project == "acme-analytics"
    error_message = "Example data-exporter project wrong"
  }
}

run "empty_config_plans_nothing" {
  command = plan

  variables {
    config_file = null
    config_yaml = "# nothing yet\n"
  }

  assert {
    condition     = length(google_service_account.this) == 0 && length(output.service_accounts) == 0
    error_message = "Empty config should plan nothing"
  }
}

# --- The validation gate fails the plan ---------------------------------------------------------

run "invalid_yaml_fails_plan" {
  command = plan

  variables {
    config_file = null
    config_yaml = <<-EOT
      project_id: good-project
      service_accounts:
        - account_id: Bad_ID
        - account_id: ok-account
          iam_bindings:
            - role: roles/iam.serviceAccountUser
              members: [ref:nobody]
    EOT
  }

  expect_failures = [output.service_accounts]
}

run "missing_input_fails_plan" {
  command = plan

  variables {
    config_file = null
    config_yaml = null
  }

  expect_failures = [output.service_accounts]
}

run "missing_config_file_fails_variable_validation" {
  command = plan

  variables {
    config_file = "tests/fixtures/does-not-exist.yaml"
  }

  expect_failures = [var.config_file]
}

run "invalid_project_variable_fails_variable_validation" {
  command = plan

  variables {
    project_id = "Not A Project"
  }

  expect_failures = [var.project_id]
}

# --- Apply lifecycle against the mocked provider -------------------------------------------------
# These runs share state, so they exercise create -> update -> destroy of
# for_each keys (renamed roles, removed accounts) across successive applies.

run "apply_initial" {
  command = apply

  variables {
    config_file = null
    config_yaml = <<-EOT
      project_id: lifecycle-proj
      service_accounts:
        - account_id: keep-me
          display_name: Keep v1
          iam_bindings:
            - role: roles/iam.serviceAccountUser
              members: [ref:remove-me, user:a@example.com]
          project_roles: [roles/viewer]
        - account_id: remove-me
          folder_roles:
            - role: roles/viewer
              folder_id: "123"
    EOT
  }

  assert {
    condition     = jsonencode(keys(output.service_accounts)) == jsonencode(["keep-me", "remove-me"])
    error_message = "Wrong accounts after apply: ${jsonencode(keys(output.service_accounts))}"
  }
  assert {
    condition     = output.service_accounts["keep-me"].display_name == "Keep v1" && output.service_accounts["keep-me"].project == "lifecycle-proj"
    error_message = "Applied attributes wrong: ${jsonencode(output.service_accounts["keep-me"])}"
  }
  assert {
    condition     = length(google_service_account_iam_member.this) == 2 && length(google_folder_iam_member.this) == 1
    error_message = "Wrong grant counts after first apply"
  }
}

run "apply_update" {
  command = apply

  variables {
    config_file = null
    config_yaml = <<-EOT
      project_id: lifecycle-proj
      service_accounts:
        - account_id: keep-me
          display_name: Keep v2
          iam_bindings:
            - role: roles/iam.serviceAccountUser
              authoritative: true
              members: [user:a@example.com, user:b@example.com]
          project_roles: [roles/browser]
    EOT
  }

  assert {
    condition     = jsonencode(keys(output.service_accounts)) == jsonencode(["keep-me"])
    error_message = "remove-me should be destroyed: ${jsonencode(keys(output.service_accounts))}"
  }
  assert {
    condition     = output.service_accounts["keep-me"].display_name == "Keep v2"
    error_message = "display_name not updated"
  }
  # Switching the role to authoritative replaces the additive members.
  assert {
    condition     = length(google_service_account_iam_member.this) == 0 && length(google_service_account_iam_binding.this) == 1
    error_message = "Additive -> authoritative switch failed"
  }
  assert {
    condition     = jsonencode(keys(google_project_iam_member.this)) == jsonencode(["keep-me|projects/lifecycle-proj|roles/browser"]) && length(google_folder_iam_member.this) == 0
    error_message = "Grants not updated: ${jsonencode(keys(google_project_iam_member.this))}"
  }
}

run "apply_full_fixture" {
  command = apply

  assert {
    condition     = length(output.service_accounts) == 4 && output.service_accounts["app-runtime"].project == "app-prod-proj"
    error_message = "Full fixture did not apply"
  }
}
