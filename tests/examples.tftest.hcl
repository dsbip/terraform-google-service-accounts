# Every example in examples/ must be valid and plan exactly what it describes.
# Expected counts were worked out by hand from each YAML file, so these runs
# check the files against their intent, not against the module's own output.
#
# Count order in assertions: [sa_iam_members, sa_iam_bindings, project, folder, organization]

mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      name   = "projects/mock-project/serviceAccounts/mock-account@mock-project.iam.gserviceaccount.com"
      email  = "mock-account@mock-project.iam.gserviceaccount.com"
      member = "serviceAccount:mock-account@mock-project.iam.gserviceaccount.com"
    }
  }
}

variables {
  config_file = null
  config_yaml = null
  project_id  = null
}

# --- examples/configs/*.yaml, one run each ---------------------------------------------

run "config_01_minimal" {
  command = plan
  variables {
    config_file = "examples/configs/01-minimal.yaml"
  }

  assert {
    condition     = jsonencode(keys(google_service_account.this)) == jsonencode(["sandbox-reporter", "sandbox-runner"])
    error_message = "Accounts: ${jsonencode(keys(google_service_account.this))}"
  }
  assert {
    condition     = jsonencode([length(google_service_account_iam_member.this), length(google_service_account_iam_binding.this), length(google_project_iam_member.this), length(google_folder_iam_member.this), length(google_organization_iam_member.this)]) == jsonencode([0, 0, 1, 0, 0])
    error_message = "Unexpected grant counts"
  }
}

run "config_02_all_principal_types" {
  command = plan
  variables {
    config_file = "examples/configs/02-all-principal-types.yaml"
  }

  assert {
    condition     = jsonencode(keys(google_service_account.this)) == jsonencode(["shared-tooling", "tooling-bot"])
    error_message = "Accounts: ${jsonencode(keys(google_service_account.this))}"
  }
  assert {
    condition     = jsonencode([length(google_service_account_iam_member.this), length(google_service_account_iam_binding.this), length(google_project_iam_member.this), length(google_folder_iam_member.this), length(google_organization_iam_member.this)]) == jsonencode([9, 0, 0, 0, 0])
    error_message = "Unexpected grant counts"
  }
  # Every principal prefix appears at least once.
  assert {
    condition = alltrue([
      for prefix in ["user:", "group:", "serviceAccount:", "domain:", "principal://", "principalSet://"] :
      anytrue([for g in google_service_account_iam_member.this : startswith(g.member, prefix)])
    ])
    error_message = "A principal kind is missing: ${jsonencode([for g in google_service_account_iam_member.this : g.member])}"
  }
  assert {
    condition     = contains([for g in google_service_account_iam_member.this : g.member], "serviceAccount:tooling-bot@acme-iam-demo.iam.gserviceaccount.com")
    error_message = "ref:tooling-bot not resolved"
  }
}

run "config_03_github_actions_wif" {
  command = plan
  variables {
    config_file = "examples/configs/03-github-actions-wif.yaml"
  }

  assert {
    condition     = jsonencode(keys(google_service_account.this)) == jsonencode(["gha-app-deployer", "gha-terraform-apply", "gha-terraform-plan"])
    error_message = "Accounts: ${jsonencode(keys(google_service_account.this))}"
  }
  assert {
    condition     = jsonencode([length(google_service_account_iam_member.this), length(google_service_account_iam_binding.this), length(google_project_iam_member.this), length(google_folder_iam_member.this), length(google_organization_iam_member.this)]) == jsonencode([2, 1, 6, 0, 0])
    error_message = "Unexpected grant counts"
  }
  assert {
    condition     = google_service_account.this["gha-terraform-apply"].deletion_policy == "PREVENT"
    error_message = "terraform-apply account should be protected"
  }
}

run "config_04_gke_workload_identity" {
  command = plan
  variables {
    config_file = "examples/configs/04-gke-workload-identity.yaml"
  }

  assert {
    condition     = jsonencode(keys(google_service_account.this)) == jsonencode(["gke-nodes", "gke-orders-worker", "gke-payments-api"])
    error_message = "Accounts: ${jsonencode(keys(google_service_account.this))}"
  }
  assert {
    condition     = jsonencode([length(google_service_account_iam_member.this), length(google_service_account_iam_binding.this), length(google_project_iam_member.this), length(google_folder_iam_member.this), length(google_organization_iam_member.this)]) == jsonencode([3, 0, 7, 0, 0])
    error_message = "Unexpected grant counts"
  }
  assert {
    condition     = alltrue([for g in google_service_account_iam_member.this : g.role == "roles/iam.workloadIdentityUser" && can(regex("^serviceAccount:acme-gke-prod\\.svc\\.id\\.goog\\[", g.member))])
    error_message = "All SA grants here should be GKE Workload Identity bindings"
  }
}

run "config_05_cloud_run_services" {
  command = plan
  variables {
    config_file = "examples/configs/05-cloud-run-services.yaml"
  }

  assert {
    condition     = jsonencode(keys(google_service_account.this)) == jsonencode(["pubsub-push-invoker", "run-api", "run-web", "scheduler-invoker"])
    error_message = "Accounts: ${jsonencode(keys(google_service_account.this))}"
  }
  assert {
    condition     = jsonencode([length(google_service_account_iam_member.this), length(google_service_account_iam_binding.this), length(google_project_iam_member.this), length(google_folder_iam_member.this), length(google_organization_iam_member.this)]) == jsonencode([2, 2, 7, 0, 0])
    error_message = "Unexpected grant counts"
  }
  assert {
    condition     = alltrue([for b in google_service_account_iam_binding.this : jsonencode(b.members) == jsonencode(["serviceAccount:gha-app-deployer@acme-ci.iam.gserviceaccount.com"])])
    error_message = "Runtime accounts should be deployable only by the CI deployer"
  }
}

run "config_06_data_platform" {
  command = plan
  variables {
    config_file = "examples/configs/06-data-platform.yaml"
  }

  assert {
    condition     = jsonencode(keys(google_service_account.this)) == jsonencode(["bi-reader", "composer-env", "dataflow-worker"])
    error_message = "Accounts: ${jsonencode(keys(google_service_account.this))}"
  }
  assert {
    condition     = jsonencode([length(google_service_account_iam_member.this), length(google_service_account_iam_binding.this), length(google_project_iam_member.this), length(google_folder_iam_member.this), length(google_organization_iam_member.this)]) == jsonencode([2, 0, 8, 2, 0])
    error_message = "Unexpected grant counts"
  }
  assert {
    condition     = length([for g in google_project_iam_member.this : g if g.project == "acme-data-lake"]) == 4
    error_message = "Expected 4 grants on the data lake project"
  }
}

run "config_07_multi_project_environments" {
  command = plan
  variables {
    config_file = "examples/configs/07-multi-project-environments.yaml"
  }

  assert {
    condition     = jsonencode(keys(google_service_account.this)) == jsonencode(["app-dev", "app-prod", "app-staging", "release-bot"])
    error_message = "Accounts: ${jsonencode(keys(google_service_account.this))}"
  }
  assert {
    condition     = jsonencode([length(google_service_account_iam_member.this), length(google_service_account_iam_binding.this), length(google_project_iam_member.this), length(google_folder_iam_member.this), length(google_organization_iam_member.this)]) == jsonencode([2, 1, 8, 0, 0])
    error_message = "Unexpected grant counts"
  }
  assert {
    condition = jsonencode({ for k, sa in google_service_account.this : k => sa.project }) == jsonencode({
      app-dev     = "acme-app-dev"
      app-prod    = "acme-app-prod"
      app-staging = "acme-app-staging"
      release-bot = "acme-shared-services"
    })
    error_message = "Projects: ${jsonencode({ for k, sa in google_service_account.this : k => sa.project })}"
  }
}

run "config_08_security_and_break_glass" {
  command = plan
  variables {
    config_file = "examples/configs/08-security-and-break-glass.yaml"
  }

  assert {
    condition     = jsonencode(keys(google_service_account.this)) == jsonencode(["break-glass-admin", "log-router-admin", "security-scanner"])
    error_message = "Accounts: ${jsonencode(keys(google_service_account.this))}"
  }
  assert {
    condition     = jsonencode([length(google_service_account_iam_member.this), length(google_service_account_iam_binding.this), length(google_project_iam_member.this), length(google_folder_iam_member.this), length(google_organization_iam_member.this)]) == jsonencode([1, 1, 0, 1, 5])
    error_message = "Unexpected grant counts"
  }
  assert {
    condition     = google_service_account.this["break-glass-admin"].disabled == true && google_service_account.this["break-glass-admin"].deletion_policy == "PREVENT"
    error_message = "Break-glass account should be disabled and protected"
  }
  assert {
    condition     = google_service_account_iam_binding.this["break-glass-admin|roles/iam.serviceAccountTokenCreator|until-end-of-2026"].condition[0].title == "until-end-of-2026"
    error_message = "Break-glass binding should be time-boxed"
  }
  assert {
    condition     = alltrue([for g in google_organization_iam_member.this : g.org_id == "987654321098"]) && google_folder_iam_member.this["log-router-admin|folders/456789012345|roles/logging.viewer"].folder == "folders/456789012345"
    error_message = "Folder/org IDs not normalized"
  }
}

run "config_09_authoritative_and_conditions" {
  command = plan
  variables {
    config_file = "examples/configs/09-authoritative-and-conditions.yaml"
  }

  assert {
    condition     = jsonencode(keys(google_service_account.this)) == jsonencode(["platform-automation", "platform-scheduler"])
    error_message = "Accounts: ${jsonencode(keys(google_service_account.this))}"
  }
  assert {
    condition     = jsonencode([length(google_service_account_iam_member.this), length(google_service_account_iam_binding.this), length(google_project_iam_member.this), length(google_folder_iam_member.this), length(google_organization_iam_member.this)]) == jsonencode([2, 1, 5, 0, 0])
    error_message = "Unexpected grant counts"
  }
  # The folded (>-) YAML expression arrives as one line joined with spaces.
  assert {
    condition     = startswith(google_service_account_iam_member.this["platform-automation|roles/iam.serviceAccountOpenIdTokenCreator|user:contractor@partner.example.com|contractor-business-hours"].condition[0].expression, "request.time < timestamp(\"2027-01-01T00:00:00Z\") && request.time.getDayOfWeek")
    error_message = "Folded condition expression not joined as expected"
  }
  assert {
    condition     = length([for g in google_project_iam_member.this : g if g.role == "roles/storage.objectViewer"]) == 2
    error_message = "Two conditional storage grants expected"
  }
}

# --- Runnable examples ----------------------------------------------------------------------

run "example_complete" {
  command = plan
  module {
    source = "./examples/complete"
  }

  assert {
    condition     = jsonencode(keys(output.emails)) == jsonencode(["app-runtime", "break-glass-admin", "ci-deployer", "data-exporter"])
    error_message = "Accounts: ${jsonencode(keys(output.emails))}"
  }
}

run "example_templated_dev" {
  command = plan
  module {
    source = "./examples/templated"
  }
  variables {
    environment = "dev"
  }

  assert {
    condition = jsonencode(output.emails) == jsonencode({
      deployer-dev = "deployer-dev@acme-web-dev.iam.gserviceaccount.com"
      web-dev      = "web-dev@acme-web-dev.iam.gserviceaccount.com"
    })
    error_message = "Emails: ${jsonencode(output.emails)}"
  }
}

run "example_templated_prod" {
  command = plan
  module {
    source = "./examples/templated"
  }
  variables {
    environment = "prod"
  }

  assert {
    condition     = jsonencode(keys(output.emails)) == jsonencode(["break-glass-prod", "deployer-prod", "web-prod"])
    error_message = "Prod should add the break-glass account: ${jsonencode(keys(output.emails))}"
  }
}

run "example_multi_file_loads_every_config" {
  command = plan
  module {
    source = "./examples/multi-file"
  }

  assert {
    condition     = length(output.emails) == 9
    error_message = "Expected one module instance per file in examples/configs: ${jsonencode(keys(output.emails))}"
  }
  assert {
    condition     = length(flatten([for f, e in output.emails : values(e)])) == 26
    error_message = "Expected 26 accounts across all example configs"
  }
}

run "example_multi_file_rejects_an_account_defined_twice" {
  command = plan
  module {
    source = "./examples/multi-file"
  }
  variables {
    config_dir = "tests/fixtures/overlapping"
  }

  expect_failures = [output.emails]
}
