# Parses the service account YAML into uniformly-typed records that the root
# module can hand straight to for_each.
#
# yamldecode() returns loosely-typed objects and tuples, and an HCL conditional
# such as `ok ? raw_value : {}` tries to unify both branches (silently turning
# mixed objects into maps). So raw YAML values are only ever read through try()
# and filtered for-expressions. The "x is a list" test used throughout is
# `!can(keys(x)) && !can(tostring(x))`.
#
# Performance: a function call costs time proportional to the size of its
# argument, so never call one on a whole collection inside a loop over that
# collection (that made 3000 entries take 36s). Compute such flags once, up
# front, as done for service_accounts_is_list, sa_list_fields and entry_items.
#
# Malformed values normalize to null or "" here; validation.tf reports them.

locals {
  # --- 1. Read and parse -------------------------------------------------------

  config_text = var.config_yaml != null ? var.config_yaml : try(file(var.config_file), "")

  # yamldecode() rejects input holding only comments/whitespace; treat it as empty.
  config_blank = trimspace(replace(local.config_text, "/(?m)^\\s*#.*$/", "")) == ""
  raw          = local.config_blank ? null : yamldecode(local.config_text)

  top_level_defaults = {
    project_id       = null
    service_accounts = null
  }
  top = try(merge(local.top_level_defaults, local.raw), local.top_level_defaults)

  file_project_id    = try(tostring(local.top.project_id), null)
  default_project_id = try(coalesce(local.file_project_id, var.project_id), null)

  # --- 2. Service accounts -----------------------------------------------------

  sa_field_defaults = {
    account_id                   = null
    project_id                   = null
    display_name                 = null
    description                  = null
    disabled                     = null
    create_ignore_already_exists = null
    deletion_policy              = null
    iam_bindings                 = null
    project_roles                = null
    folder_roles                 = null
    organization_roles           = null
  }

  service_accounts_is_list = !can(keys(local.top.service_accounts)) && !can(tostring(local.top.service_accounts))
  sa_items                 = try([for item in local.top.service_accounts : item if local.service_accounts_is_list], [])

  # Raw view of each list item with every known field present (null when unset).
  sa_raw = [
    for i, item in local.sa_items : {
      index          = i
      is_map         = can(keys(item))
      unknown_fields = sort([for f in try(keys(item), []) : f if !contains(keys(local.sa_field_defaults), f)])
      fields         = try(merge(local.sa_field_defaults, item), local.sa_field_defaults)
    }
  ]

  sa_scalars = [
    for s in local.sa_raw : {
      index                        = s.index
      account_id                   = try(tostring(s.fields.account_id), null)
      own_project_id               = try(tostring(s.fields.project_id), null)
      project_id                   = try(coalesce(try(tostring(s.fields.project_id), null), local.default_project_id), null)
      display_name                 = try(tostring(s.fields.display_name), null)
      description                  = try(tostring(s.fields.description), null)
      disabled                     = try(tobool(s.fields.disabled), null)
      create_ignore_already_exists = try(tobool(s.fields.create_ignore_already_exists), null)
      deletion_policy              = try(tostring(s.fields.deletion_policy), null)
    }
  ]

  # Adds the label used in error messages and the email GCP will assign. Emails
  # are derived locally (not read back from the resource) so they are known at
  # plan time and can be used in for_each keys; tests/provider_plan.tftest.hcl
  # checks they match what the real provider computes.
  sa_records = [
    for s in local.sa_scalars : merge(s, {
      label = s.account_id == null ? "service_accounts[${s.index}]" : "service_accounts[${s.index}] (${s.account_id})"
      email = try("${s.account_id}@${s.project_id}.iam.gserviceaccount.com", null)
    })
  ]

  # Grouped so a duplicated account_id cannot break the map; validation.tf reports it.
  sa_by_account_id = {
    for s in local.sa_records : s.account_id => s... if s.account_id != null && s.account_id != ""
  }
  service_accounts = { for k, group in local.sa_by_account_id : k => group[0] }

  # --- 3. Role entries: iam_bindings and the *_roles lists -----------------------

  entry_kinds = {
    iam_bindings       = { allowed_fields = ["authoritative", "condition", "members", "role"], target_field = "" }
    project_roles      = { allowed_fields = ["condition", "project_id", "role", "roles"], target_field = "project_id" }
    folder_roles       = { allowed_fields = ["condition", "folder_id", "role", "roles"], target_field = "folder_id" }
    organization_roles = { allowed_fields = ["condition", "org_id", "role", "roles"], target_field = "org_id" }
  }
  entry_kind_order = ["iam_bindings", "project_roles", "folder_roles", "organization_roles"]
  condition_fields = ["description", "expression", "title"]

  # Per service account: is each role-list field a real YAML list?
  sa_list_fields = [
    for s in local.sa_raw : {
      for kind in local.entry_kind_order : kind => !can(keys(s.fields[kind])) && !can(tostring(s.fields[kind]))
    }
  ]

  # One item per list entry, with the entry's own list checks done once.
  entry_items = flatten([
    for s in local.sa_raw : [
      for kind in local.entry_kind_order : [
        for i, e in try([for x in s.fields[kind] : x if local.sa_list_fields[s.index][kind]], []) : {
          kind            = kind
          sa_index        = s.index
          index           = i
          raw             = e
          roles_is_list   = try(!can(keys(e.roles)) && !can(tostring(e.roles)) && can(length(e.roles)), false)
          members_is_list = try(!can(keys(e.members)) && !can(tostring(e.members)) && can(length(e.members)), false)
        }
      ]
    ]
  ])

  entries_raw = [
    for it in local.entry_items : {
      kind           = it.kind
      sa_index       = it.sa_index
      sa_key         = local.sa_records[it.sa_index].account_id
      sa_project_id  = local.sa_records[it.sa_index].project_id
      sa_member      = try("serviceAccount:${local.sa_records[it.sa_index].email}", null)
      path           = "${local.sa_records[it.sa_index].label}.${it.kind}[${it.index}]"
      is_string      = try(it.raw != null && can(tostring(it.raw)), false)
      is_map         = can(keys(it.raw))
      unknown_fields = sort([for f in try(keys(it.raw), []) : f if !contains(local.entry_kinds[it.kind].allowed_fields, f)])

      # `role` (all kinds), `roles` (grant kinds) and the bare-string shorthand
      # (grant kinds) all collapse into one list. Non-string roles become "".
      has_role      = try(it.raw.role != null, false)
      has_roles     = try(it.raw.roles != null, false)
      roles_is_list = it.roles_is_list
      roles = (
        it.kind != "iam_bindings" && try(it.raw != null && can(tostring(it.raw)), false) ? [tostring(it.raw)] : concat(
          try(it.raw.role == null ? [] : [try(tostring(it.raw.role), "")], []),
          it.kind == "iam_bindings" ? [] : try([for r in it.raw.roles : try(tostring(r), "") if it.roles_is_list], []),
        )
      )

      has_members     = try(it.raw.members != null, false)
      members_is_list = it.members_is_list
      members         = try([for m in it.raw.members : try(tostring(m), "") if it.members_is_list], [])

      has_authoritative     = try(it.raw.authoritative != null, false)
      authoritative_is_bool = can(tobool(it.raw.authoritative))
      authoritative         = try(tobool(it.raw.authoritative), false)

      has_target  = try(it.raw[local.entry_kinds[it.kind].target_field] != null, false)
      target_raw  = try(tostring(it.raw[local.entry_kinds[it.kind].target_field]), null)
      target_json = try(jsonencode(it.raw[local.entry_kinds[it.kind].target_field]), "null")

      has_condition     = try(it.raw.condition != null, false)
      condition_is_map  = can(keys(it.raw.condition))
      condition_unknown = sort([for f in try(keys(it.raw.condition), []) : f if !contains(local.condition_fields, f)])
      condition = try(it.raw.condition != null, false) ? {
        title       = try(tostring(it.raw.condition.title), null)
        description = try(tostring(it.raw.condition.description), null)
        expression  = try(tostring(it.raw.condition.expression), null)
      } : null
    }
  ]

  entries = [
    for e in local.entries_raw : merge(e, {
      # ref:<account_id> points at a service account defined in the same YAML.
      # Only fully valid accounts resolve; a ref to a broken one stays "ref:..."
      # and is never handed on (the broken account itself is reported).
      members_resolved = [
        for m in e.members :
        startswith(m, "ref:") ? try("serviceAccount:${local.buildable_service_accounts[trimprefix(m, "ref:")].email}", m) : m
      ]

      # project_roles default to the service account's own project; folder and
      # organization IDs accept an optional "folders/" / "organizations/" prefix.
      target = (
        e.kind == "project_roles" ? try(coalesce(e.target_raw, e.sa_project_id), null) :
        e.kind == "folder_roles" ? try("folders/${trimprefix(e.target_raw, "folders/")}", null) :
        e.kind == "organization_roles" ? try(trimprefix(e.target_raw, "organizations/"), null) :
        null
      )
    })
  ]

  # --- 4. One record per IAM resource ---------------------------------------------
  # Keys read like "<account_id>|<scope>|<role>|<member>|<condition title>" so plan
  # output is self-explanatory. Records are grouped by key: exact duplicates
  # collapse into one resource, differing ones are reported by validation.tf.

  sa_iam_member_records = flatten([
    for e in local.entries : [
      for role in e.roles : [
        for m in e.members_resolved : {
          key       = join("|", compact([e.sa_key, role, m, try(e.condition.title, "")]))
          sa_key    = e.sa_key
          role      = role
          member    = m
          condition = e.condition
          path      = e.path
        }
      ]
    ] if e.kind == "iam_bindings" && !e.authoritative
  ])

  sa_iam_binding_records = flatten([
    for e in local.entries : [
      for role in e.roles : {
        key       = join("|", compact([e.sa_key, role, try(e.condition.title, "")]))
        sa_key    = e.sa_key
        role      = role
        members   = sort(distinct(e.members_resolved))
        condition = e.condition
        path      = e.path
      }
    ] if e.kind == "iam_bindings" && e.authoritative
  ])

  grant_scope_prefix = {
    project_roles      = "projects/"
    folder_roles       = "" # target already carries "folders/"
    organization_roles = "organizations/"
  }

  resource_grant_records = flatten([
    for e in local.entries : [
      for role in e.roles : {
        kind      = e.kind
        key       = join("|", compact([e.sa_key, try("${local.grant_scope_prefix[e.kind]}${e.target}", ""), role, try(e.condition.title, "")]))
        sa_key    = e.sa_key
        target    = e.target
        role      = role
        member    = e.sa_member
        condition = e.condition
        path      = e.path
      }
    ] if e.kind != "iam_bindings"
  ])

  sa_iam_member_groups  = { for r in local.sa_iam_member_records : r.key => r... }
  sa_iam_binding_groups = { for r in local.sa_iam_binding_records : r.key => r... }
  resource_grant_groups = { for r in local.resource_grant_records : r.key => r... }

  # --- 5. Hand-off to the root module ------------------------------------------------
  # Only records whose resource is fully valid are passed on. Anything else only
  # exists alongside validation errors (which fail the plan), and dropping it
  # keeps provider-level noise out of the plan so users see one clean error list.

  # Membership checks below index these maps (can(map[key])) rather than
  # scanning lists, so validation stays linear for files with hundreds of accounts.
  buildable_service_accounts = {
    for k, s in local.service_accounts : k => s
    if can(regex(local.re_account_id, k)) && can(regex(local.re_project_id, s.project_id))
  }

  grant_target_regex = {
    project_roles      = local.re_project_id
    folder_roles       = "^folders/[0-9]+$"
    organization_roles = "^[0-9]+$"
  }

  sa_iam_members = {
    for k, g in local.sa_iam_member_groups : k => {
      sa_key    = g[0].sa_key
      role      = g[0].role
      member    = g[0].member
      condition = g[0].condition
    }
    if can(local.buildable_service_accounts[g[0].sa_key])
    && can(regex(local.re_role, g[0].role))
    && can(regex(local.re_member, g[0].member)) && !startswith(g[0].member, "ref:")
  }

  sa_iam_bindings = {
    for k, g in local.sa_iam_binding_groups : k => {
      sa_key    = g[0].sa_key
      role      = g[0].role
      members   = g[0].members
      condition = g[0].condition
    }
    if can(local.buildable_service_accounts[g[0].sa_key])
    && can(regex(local.re_role, g[0].role))
    && length(g[0].members) > 0
    && alltrue([for m in g[0].members : can(regex(local.re_member, m)) && !startswith(m, "ref:")])
  }

  resource_grants = {
    for k, g in local.resource_grant_groups : k => g[0]
    if can(local.buildable_service_accounts[g[0].sa_key])
    && can(regex(local.re_role, g[0].role))
    && can(regex(local.grant_target_regex[g[0].kind], g[0].target))
  }
}
