# Plans against the REAL google provider (not a mock), offline. A dummy
# access_token lets the provider configure without calling Google, and planning
# brand-new resources makes no API calls. No apply happens here: every run is
# command = plan.
#
# This catches what mocks cannot: the provider's own argument validation on
# the real plan path, and that the emails the module derives locally match
# the emails the provider computes (the provider exposes email/member at plan).

provider "google" {
  access_token = "offline-plan-only-dummy-token"
  project      = "offline-plan-project"
}

variables {
  config_file = "tests/fixtures/complete.yaml"
  config_yaml = null
  project_id  = null
}

run "real_provider_accepts_every_argument" {
  command = plan

  assert {
    condition     = length(google_service_account.this) == 4 && length(google_service_account_iam_member.this) == 10 && length(google_project_iam_member.this) == 7
    error_message = "Real-provider plan produced unexpected resource counts"
  }
}

run "local_emails_match_provider_emails" {
  command = plan

  assert {
    condition     = alltrue([for k, sa in google_service_account.this : sa.email == output.emails[k]])
    error_message = "Derived emails differ from provider emails: ${jsonencode({ for k, sa in google_service_account.this : k => [sa.email, output.emails[k]] })}"
  }
  assert {
    condition     = alltrue([for k, sa in google_service_account.this : sa.member == output.members[k]])
    error_message = "Derived members differ from provider members"
  }
}

run "real_provider_plans_the_example" {
  command = plan

  variables {
    config_file = "examples/complete/service_accounts.yaml"
  }

  assert {
    condition     = alltrue([for k, sa in google_service_account.this : sa.email == output.emails[k]])
    error_message = "Example emails differ from provider emails"
  }
}

# All nine examples/configs/*.yaml at once, through the multi-file example.
run "real_provider_plans_every_example_config" {
  command = plan
  module {
    source = "./examples/multi-file"
  }

  assert {
    condition     = length(flatten([for f, accounts in output.service_accounts : keys(accounts)])) == 26
    error_message = "Expected 26 accounts across examples/configs"
  }
  assert {
    condition     = alltrue(flatten([for f, accounts in output.service_accounts : [for k, sa in accounts : sa.email == output.emails[f][k]]]))
    error_message = "Derived emails differ from provider emails in examples/configs"
  }
}

run "real_provider_plans_the_templated_example" {
  command = plan
  module {
    source = "./examples/templated"
  }
  variables {
    environment = "prod"
  }

  assert {
    condition     = output.emails["break-glass-prod"] == "break-glass-prod@acme-web-prod.iam.gserviceaccount.com"
    error_message = "Templated prod example did not plan as expected: ${jsonencode(output.emails)}"
  }
}
