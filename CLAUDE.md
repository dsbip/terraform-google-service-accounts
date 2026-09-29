# GCP service accounts from YAML (Terraform module)

This Terraform module creates Google Cloud service accounts and their IAM role
bindings from **one YAML file**. A file can define any number of service
accounts, each with its own settings and bindings, in two directions:

- **`iam_bindings`**: principals granted roles **on** a service account (who may
  impersonate it, deploy as it, mint tokens for it, and so on). Supported
  principals are users, groups, other service accounts, whole domains, GKE
  Workload Identity, Workload/Workforce Identity Federation, and other service
  accounts in the same file.
- **`project_roles` / `folder_roles` / `organization_roles`**: roles granted
  **to** a service account on projects, folders and organizations.

The YAML is fully validated before anything is planned. Every mistake is
reported at once, with its exact path in the file.

---

## Quick start

```hcl
module "service_accounts" {
  source = "path/to/this/repo"

  config_file = "${path.module}/service_accounts.yaml"
  project_id  = "my-project" # optional fallback, see "Project resolution"
}
```

```yaml
# service_accounts.yaml
project_id: my-project

service_accounts:
  - account_id: ci-deployer
    display_name: CI deployer
    iam_bindings:
      - role: roles/iam.workloadIdentityUser
        members:
          - principalSet://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/github/attribute.repository/acme/app
    project_roles:
      - roles/run.developer

  - account_id: app-runtime
    iam_bindings:
      - role: roles/iam.serviceAccountUser
        members: [ref:ci-deployer]        # the SA defined above
    project_roles:
      - roles/logging.logWriter
```

More complete, commented configs are listed under [Examples](#examples).

## Examples

**Example YAML configs** in [examples/configs/](examples/configs/). Each file stands alone and uses its own
projects, so any of them can be copied as a starting point:

| File | Shows |
|---|---|
| [01-minimal.yaml](examples/configs/01-minimal.yaml) | The smallest valid configs: a bare account, then one with a name and a single role |
| [02-all-principal-types.yaml](examples/configs/02-all-principal-types.yaml) | Every accepted member format side by side: `user:`, `group:`, `serviceAccount:`, `domain:`, `principal://`, `principalSet://` (workload and workforce pools), GKE KSA, `ref:` |
| [03-github-actions-wif.yaml](examples/configs/03-github-actions-wif.yaml) | Keyless CI/CD from GitHub Actions: repo-scoped plan account, main-branch-only apply account (authoritative, `PREVENT`), app deployer |
| [04-gke-workload-identity.yaml](examples/configs/04-gke-workload-identity.yaml) | One Google account per Kubernetes service account, conditional secret access, least-privilege node pool account |
| [05-cloud-run-services.yaml](examples/configs/05-cloud-run-services.yaml) | Runtime account per service, deployable only by the CI deployer; Cloud Scheduler and Pub/Sub push invokers |
| [06-data-platform.yaml](examples/configs/06-data-platform.yaml) | Composer → Dataflow `actAs` chain via `ref:`, cross-project data lake grants, `roles:` lists, folder-wide read access |
| [07-multi-project-environments.yaml](examples/configs/07-multi-project-environments.yaml) | dev / staging / prod accounts in one file with per-account `project_id` and a shared release bot |
| [08-security-and-break-glass.yaml](examples/configs/08-security-and-break-glass.yaml) | Org-level security scanner and log router; disabled, protected break-glass account with a time-boxed authoritative binding |
| [09-authoritative-and-conditions.yaml](examples/configs/09-authoritative-and-conditions.yaml) | Additive vs authoritative, a multi-line condition (`>-`), the same role under two condition titles (OR), custom project/org roles |

**Runnable root modules** in [examples/](examples/):

| Example | Shows |
|---|---|
| [complete](examples/complete/main.tf) | The basic call: `config_file` pointing at [service_accounts.yaml](examples/complete/service_accounts.yaml) |
| [templated](examples/templated/main.tf) | `config_yaml = templatefile(...)`: one [YAML template](examples/templated/service_accounts.yaml.tftpl) rendered per environment (`-var environment=prod` adds a break-glass account) |
| [multi-file](examples/multi-file/main.tf) | `for_each` over every `*.yaml` in a directory (one module instance per file). A plan-time check fails if two files define the same account. |

Every example is exercised by `tests/examples.tftest.hcl`. Each file's expected
accounts and grant counts there were worked out by hand from the YAML.

## Requirements

| | Version | Why |
|---|---|---|
| Terraform | `>= 1.5.0` to use the module | verified with 1.5.7 (real offline plan) |
| Terraform | `>= 1.7.0` to run the tests | `mock_provider` / `mock_resource` in tests; verified with 1.7.0 |
| `hashicorp/google` | `>= 7.33.0, < 9.0.0` | 7.33.0 added `deletion_policy` to `google_service_account` (7.32.0 verified to reject it) |

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `config_file` | `string` | `null` | Path to the YAML file. Relative paths resolve from the directory Terraform runs in, so pass `"${path.module}/file.yaml"`. Must exist. |
| `config_yaml` | `string` | `null` | The same YAML as a string, e.g. `templatefile("sa.yaml.tftpl", {...})` to reuse one template across environments. |
| `project_id` | `string` | `null` | Last-resort project for service accounts and `project_roles` that don't resolve a project from the YAML. |

Set **exactly one** of `config_file` / `config_yaml`.

## Outputs

| Name | Description |
|---|---|
| `service_accounts` | Map `account_id` → `{account_id, email, member, id, name, unique_id, project, display_name, disabled}` read from the created resources. The validation gate is attached to this output (see [Validation](#validation)). |
| `emails` | Map `account_id` → email. **Known at plan time**, so it is safe to use in downstream `for_each`. Depends on the service accounts, so consumers are ordered after creation. |
| `members` | Map `account_id` → `serviceAccount:<email>`. Known at plan time. |

---

## YAML schema

### Top level

| Key | Required | Description |
|---|---|---|
| `project_id` | no | Default project for every service account in the file. |
| `service_accounts` | no | **List** of service account definitions. Empty, `[]`, or missing means no service accounts. |

A blank file, or one holding only comments or `---`, is valid and manages nothing.
Unknown top-level keys are errors, so a typo like `service_account:` can't be silently ignored.

### Service account fields

Each list item is a mapping:

| Field | Required | Type | Notes |
|---|---|---|---|
| `account_id` | **yes** | string | 6–30 chars, `^[a-z][-a-z0-9]{4,28}[a-z0-9]$`. Unique per file. It is the resource key (`google_service_account.this["<account_id>"]`) and the name `ref:` uses. |
| `project_id` | no | string | Overrides the file-level `project_id`. See [Project resolution](#project-resolution). |
| `display_name` | no | string | ≤ 100 **UTF-8 bytes** (the IAM API limit). Non-ASCII characters count 2–4 bytes each. |
| `description` | no | string | ≤ 256 UTF-8 bytes. |
| `disabled` | no | bool | Provider default `false`. |
| `create_ignore_already_exists` | no | bool | Adopt an existing service account with the same email instead of failing with 409. |
| `deletion_policy` | no | `DELETE` \| `PREVENT` \| `ABANDON` | `PREVENT` makes `terraform destroy`/removal fail. Unlike `lifecycle.prevent_destroy`, it can be set per account. |
| `iam_bindings` | no | list | Principals granted roles **on this service account**. |
| `project_roles` | no | list | Roles granted **to this service account** on projects. |
| `folder_roles` | no | list | Roles granted to this service account on folders. |
| `organization_roles` | no | list | Roles granted to this service account on organizations. |

Unset optional fields are passed to the provider as `null`, so the provider's own defaults apply.

### `iam_bindings`: principals granted roles on the service account

```yaml
iam_bindings:
  - role: roles/iam.serviceAccountUser     # required
    members:                               # required, non-empty list
      - user:alice@example.com
      - ref:ci-deployer
    authoritative: false                   # optional, default false
    condition:                             # optional IAM condition
      title: business-hours                # required in a condition
      description: Working hours only      # optional
      expression: request.time.getHours("Europe/Berlin") < 18
```

**Principal kinds accepted in `members`:**

| Form | Principal |
|---|---|
| `user:alice@example.com` | Google account |
| `group:team@example.com` | Google group |
| `serviceAccount:bot@proj.iam.gserviceaccount.com` | Any service account (including other projects) |
| `serviceAccount:PROJECT.svc.id.goog[NAMESPACE/KSA]` | GKE Workload Identity (Kubernetes SA), normally with `roles/iam.workloadIdentityUser` |
| `domain:example.com` | Everyone in a Google Workspace / Cloud Identity domain |
| `principal://iam.googleapis.com/...` | A single federated identity (Workload or Workforce Identity Federation) |
| `principalSet://iam.googleapis.com/...` | A set of federated identities, e.g. all GitHub Actions runs of one repo |
| `ref:<account_id>` | A service account **defined in the same file**. Resolved to `serviceAccount:<its email>`, and may reference itself. Accounts in other files or modules need the full `serviceAccount:` form. |

`allUsers` and `allAuthenticatedUsers` are **rejected** on purpose: a public
principal able to use a service account is effectively a public credential.

**Additive vs authoritative:**

- **Additive** (default) → one `google_service_account_iam_member` per
  principal. It adds the principal and never removes anyone added outside Terraform.
- **`authoritative: true`** → one `google_service_account_iam_binding` per role
  (and condition). The listed members become the **only** members of that role
  on the service account; anyone else is removed.
- The provider forbids mixing both modes for the same role on the same account,
  so the module rejects it.
- Two authoritative bindings for the same role and condition title are also
  rejected: merge them into one entry.
- Authoritative bindings for the same role with **different** condition titles
  are allowed.

### `project_roles` / `folder_roles` / `organization_roles`: roles granted to the service account

Each entry is one of three forms:

```yaml
project_roles:
  - roles/logging.logWriter                  # 1. bare role string (SA's own project)
  - role: roles/storage.objectViewer         # 2. single role
    project_id: shared-artifacts             #    optional target override
  - roles:                                   # 3. several roles, same target/condition
      - roles/monitoring.metricWriter
      - roles/cloudtrace.agent
    condition: {title: ..., expression: ...} #    optional, applies to each role

folder_roles:
  - role: roles/resourcemanager.folderViewer
    folder_id: "123456789012"                # required; "folders/123..." also accepted

organization_roles:
  - role: roles/iam.securityReviewer
    org_id: "987654321098"                   # required; "organizations/987..." also accepted
```

- Use `role` **or** `roles` in an entry, never both.
- The target key is per list: `project_id` (optional; defaults to the service
  account's project), `folder_id` (required), or `org_id` (required).
- Role names can be predefined (`roles/NAME`), custom project roles
  (`projects/PROJECT/roles/NAME`), or custom org roles (`organizations/ORG_ID/roles/NAME`).
- Numeric IDs may be unquoted YAML numbers. Quoting them is still recommended.

### IAM conditions

`condition` works in every entry type. `title` and `expression` are required and
`description` is optional. Conditions are keyed by **title**, which means:

- The same role and principal with **different** titles gives separate grants.
  For example, `roles/secretmanager.secretAccessor` twice, scoped to different
  secret prefixes.
- Reusing a title with a different expression or description for the same role
  and principal is an error.

### Project resolution

A service account's project is the first of these that is set:

1. the account's `project_id`
2. the file's top-level `project_id`
3. the module's `project_id` variable

If none is set, that's a validation error. The **provider's default project is
never used**, because emails must be derivable from the YAML alone.
A `project_roles` entry without `project_id` targets its service account's project.

**Domain-scoped project IDs (`example.com:my-project`) are not supported and are
rejected.** The google provider derives the plan-time email for them as
`sa@example.com:my-project.iam.gserviceaccount.com`, which isn't a valid email,
and GCP's real format for these legacy projects couldn't be confirmed.

### Duplicates

Entries that are exactly identical (the same member twice, or the same grant
twice) collapse into one resource. Duplicate `account_id`s are an error.

---

## Resources and addresses

Every resource uses `for_each` with readable keys, so plans are easy to review and
`terraform import` / `moved` blocks are easy to write:

| Resource | Key format | Example |
|---|---|---|
| `google_service_account.this` | `account_id` | `["ci-deployer"]` |
| `google_service_account_iam_member.this` | `account_id\|role\|member[\|condition title]` | `["ci-deployer\|roles/iam.serviceAccountTokenCreator\|user:alice@example.com"]` |
| `google_service_account_iam_binding.this` | `account_id\|role[\|condition title]` | `["app-runtime\|roles/iam.serviceAccountUser"]` |
| `google_project_iam_member.this` | `account_id\|projects/ID\|role[\|condition title]` | `["ci-deployer\|projects/acme-app-prod\|roles/run.developer"]` |
| `google_folder_iam_member.this` | `account_id\|folders/ID\|role[\|condition title]` | `["data-exporter\|folders/123456789012\|roles/resourcemanager.folderViewer"]` |
| `google_organization_iam_member.this` | `account_id\|organizations/ID\|role[\|condition title]` | `["break-glass-admin\|organizations/987654321098\|roles/iam.securityReviewer"]` |

Keys contain the **resolved** member, so `ref:app-runtime` appears as
`serviceAccount:app-runtime@<project>.iam.gserviceaccount.com`.

**Changing `account_id` or `project_id` replaces the service account.** The new
account gets a new `unique_id`, and every binding that references it is recreated.
Use `deletion_policy: PREVENT` on accounts that must not be destroyed by accident.

**`create_ignore_already_exists: true` adopts an existing account into state.**
From then on Terraform owns it, so removing it from the YAML **deletes** it,
even though Terraform didn't originally create it.

---

## Validation

The module checks the whole file and fails the plan with **one error listing
every problem**, each prefixed with its path. Nothing is created or changed
until the file is clean. For example, from a real `terraform plan`:

```
Error: Module output value precondition failed
...
Invalid service account configuration in bad.yaml:
  - service_accounts[0] (CI_Deployer): unknown key(s) "iam_binding" (allowed: account_id, create_ignore_already_exists, ...)
  - service_accounts[0] (CI_Deployer): account_id "CI_Deployer" must be 6-30 characters: a lowercase letter, then lowercase letters, digits or hyphens, not ending in a hyphen
  - service_accounts[1] (app-runtime).iam_bindings[0].members[0]: "alice@example.com" is not a supported principal (use user:, group:, serviceAccount:, domain:, principal://, principalSet:// or ref:<account_id>)
  - service_accounts[1] (app-runtime).iam_bindings[0].members[1]: "ref:ci-deploy" does not match any account_id in this file
  - service_accounts[1] (app-runtime).folder_roles[0]: folder_id is required
```

**What's checked:**
- Structure and types, including unknown keys at every level (typos).
- Required fields.
- ID formats: account, project, folder, org, and role names.
- Principal formats, and that every `ref:` target exists. A `ref:` to an account
  that is itself invalid is not resolved; only that account's own error is reported.
- Length limits (in UTF-8 bytes, like the API) and enum values.
- Duplicate `account_id`s.
- Conflicting duplicate grants.
- Mixed authoritative and additive grants for the same role.

---

## Design decisions and gotchas

These are the non-obvious decisions. Keep them in mind when changing the module.

- **`service_accounts` is a list, not a map.** Terraform's `yamldecode` silently
  keeps the **last** of any duplicate mapping keys. With a map, a copy-pasted
  block whose key wasn't renamed would silently replace the first account. In a
  list, duplicates are detected. The same limitation still applies to duplicate
  keys **inside** one mapping (e.g. two `project_roles:` keys in one account):
  the last one wins and no Terraform code can see it. Run
  [yamllint](https://yamllint.readthedocs.io/) with `key-duplicates` in CI if
  that matters to you.
- **Parsing and validation live in [modules/config](modules/config)**, a pure
  module with no provider and no resources. The root module only maps its outputs
  to resources. This split is what makes it possible to unit-test every error
  message exactly.
- **The validation gate is a `precondition` on the root `service_accounts`
  output.** That prints the error list once rather than once per resource, and
  adds no extra resource to state. Records that are only partly valid are also
  left out of the resource maps, so the provider doesn't add its own
  errors on top of the list.
- **Emails are derived locally** (`<account_id>@<project>.iam.gserviceaccount.com`)
  rather than read from the resource. That makes them known at plan time, so they
  can appear in `for_each` keys and the `emails`/`members` outputs. The project,
  folder and org grants therefore use `depends_on = [google_service_account.this]`
  to be ordered after the accounts exist.
  `tests/provider_plan.tftest.hcl` checks the derived emails equal what the real
  provider computes.
- **HCL conditionals unify their branch types.** `cond ? raw_yaml_value : {}`
  silently converts mixed YAML objects into maps. That's why
  [modules/config/main.tf](modules/config/main.tf) reads raw YAML only through
  `try()` and filtered `for` expressions. Keep to that when adding fields.
- **Never call a function on a whole collection inside a loop over that same
  collection.** Function calls cost time proportional to the size of their
  argument, so `[for x in list : x if !can(keys(list))]` is quadratic. That
  pattern made one account with 3,000 grants take 36 s to parse. Compute such
  flags once, up front (`service_accounts_is_list`, `sa_list_fields`,
  `entry_items`), and use map lookups (`can(map[key])`) instead of
  `contains(list, x)`.

  Measured parse times after the fix:

  | Config | Parse time |
  |---|---|
  | 400 accounts / 3,600 grants | ≈3 s |
  | 800 accounts | <1 s |
  | 1 account with 3,000 grants | ≈2.7 s |

  Split very large configs across files with the [multi-file](examples/multi-file/main.tf) pattern.
- **One YAML document per file.** `yamldecode` does not accept several
  `---`-separated documents.
- **YAML 1.1 quirks**: `yes`/`no`/`on`/`off` are booleans. Unquoted `- group:`
  (with the trailing colon) parses as a mapping, not a string. Quote anything
  ambiguous.
- **Service account keys are intentionally not supported.** Prefer Workload
  Identity Federation (`principalSet://…`) or impersonation.
- New service accounts are eventually consistent in IAM. The provider polls after
  creation, but a very first apply can occasionally need a re-run.

---

## Repository layout

```
.
├── main.tf / variables.tf / outputs.tf / versions.tf   root module: resources + validation gate
├── modules/config/                                     pure YAML parser + validator (no provider)
│   ├── main.tf          parse → normalize → one record per IAM resource
│   ├── validation.tf    every rule; produces the `errors` list
│   └── outputs.tf       normalized maps consumed by the root module
├── examples/
│   ├── configs/*.yaml   nine scenario configs (see Examples)
│   ├── complete/        basic root module + YAML
│   ├── templated/       config_yaml + templatefile(), one template per environment
│   └── multi-file/      one module instance per YAML file, duplicate-account check
└── tests/
    ├── fixtures/complete.yaml          uses every feature
    ├── fixtures/overlapping/           two files defining the same account (multi-file check)
    ├── config_parsing.tftest.hcl       normalization results (16 runs)
    ├── config_validation.tftest.hcl    exact error messages for every rule (25 runs)
    ├── examples.tftest.hcl             every example config and runnable example (14 runs)
    ├── module.tftest.hcl               resources with a mocked provider, plan + apply lifecycle (15 runs)
    └── provider_plan.tftest.hcl        REAL provider, offline plan with a dummy token (5 runs)
```

## Testing

```sh
terraform init
terraform test                                              # all 75 runs, no GCP access needed
terraform test -filter=tests/config_validation.tftest.hcl   # one file
terraform fmt -recursive -check
```

On Windows the filter needs backslashes: `-filter='tests\config_validation.tftest.hcl'`.
Re-run `terraform init` after adding a test file that uses a `module {}` block.

**No test touches GCP.**
- `mock_provider` replaces the provider in `module.tftest.hcl` and
  `examples.tftest.hcl`. Its `mock_resource` defaults give service accounts a
  realistic `name`, because the provider still validates `service_account_id`
  even under mocks.
- `provider_plan.tftest.hcl` uses the real provider with
  `access_token = "offline-plan-only-dummy-token"`. It only plans new resources,
  which needs no API calls. Run it with `GOOGLE_APPLICATION_CREDENTIALS` unset if
  you want to be sure no real credentials are picked up.

**Suites:**

| Suite | Covers |
|---|---|
| `config_parsing` | Full fixture normalization; all principal kinds; `ref:` resolution (including to itself); conditions; authoritative member dedupe/sort; role shorthand and `roles:` expansion; folder/org ID normalization; project precedence; blank, comment-only, `---` and empty-list files; YAML scalar coercion; `config_file` ≡ `config_yaml`. |
| `config_validation` | Each rule asserts the **exact, complete** error list, so any new, missing or reworded message fails. Includes UTF-8 byte limits with multi-byte text. Also checks that invalid records, including `ref:`s to broken accounts, are never passed to the root module. |
| `examples` | Each `examples/configs/*.yaml` plans the hand-counted accounts and grant counts. The `complete`, `templated` (dev and prod) and `multi-file` examples plan, and multi-file rejects an account defined in two files. |
| `module` | Resource counts and arguments for every resource type; condition blocks; the `config_yaml` input; the gate failing the plan (`expect_failures`); variable validation; an apply → update → destroy lifecycle (removed account, additive → authoritative switch, changed roles). |
| `provider_plan` | The real provider accepts every argument for the fixture and **all** examples, and the locally derived emails/members match the provider's plan-time values. |

**Verification done (2026-09-29):**
- All 75 runs pass on Terraform **1.16.4** and **1.7.0**, and on google provider
  **8.4.0** and **7.33.0**.
- Provider **7.32.0** is rejected (`deletion_policy` unsupported), which
  confirms the version floor.
- Terraform **1.5.7** plans every runnable example: complete 22 resources,
  templated prod 10, multi-file 105. Each matches a hand count. It also shows
  both the validation error and the multi-file duplicate error correctly.
- Mutation testing: 14 bugs were planted one at a time and **all 14 were caught**:
  - `ref:` resolution removed
  - unknown-key check removed
  - `authoritative` ignored
  - folder prefix normalization removed
  - project precedence swapped
  - gate disabled
  - dedupe broken
  - public principals allowed
  - byte limits counted as characters
  - `ref:` resolving to broken accounts
  - multi-file duplicate check disabled
  - list-shape check dropped
  - grant target filter removed
  - authoritative members unsorted
- Scale: see the performance note under [Design decisions](#design-decisions-and-gotchas).
- **Not yet done: a live apply against a real GCP project.** To run one, apply
  [examples/complete](examples/complete) against a sandbox project after
  replacing the placeholder IDs (`acme-*`, `123456789012`, `example.com`).
  Destroy it afterwards; mind any `deletion_policy: PREVENT` accounts, which
  must be switched to `DELETE` before destroy.

### Adding a YAML field (checklist)

1. **Service account field:** add it to `sa_field_defaults` and `sa_scalars` in
   [modules/config/main.tf](modules/config/main.tf). **Entry field:** add it to
   `entry_kinds[*].allowed_fields` and `entries_raw`, reading it from `it.raw`.
2. Add type/format rules to [modules/config/validation.tf](modules/config/validation.tf).
3. Expose it in [modules/config/outputs.tf](modules/config/outputs.tf) and wire it
   into the resource in [main.tf](main.tf).
4. Add it to `tests/fixtures/complete.yaml` and assert it in
   `config_parsing` and `module`. Add an exact-message run to `config_validation`.
   Update the expected `unknown key(s) … (allowed: …)` strings, which list every
   allowed key.
5. Document it in the schema tables above.
