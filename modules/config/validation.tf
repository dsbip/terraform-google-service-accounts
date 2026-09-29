# Collects every problem in the YAML as "<path>: <message>" strings. The root
# module turns a non-empty list into a single plan-time error, so users see all
# mistakes at once. Raw values are shown via jsonencode() so they appear exactly
# as written (quoted strings, lists, numbers).

locals {
  re_account_id = "^[a-z][-a-z0-9]{4,28}[a-z0-9]$"
  # Domain-scoped projects ("example.com:proj") are deliberately rejected: the
  # provider derives an invalid plan-time email for them (see CLAUDE.md).
  re_project_id = "^[a-z][-a-z0-9]{4,28}[a-z0-9]$"
  re_role       = "^(?:roles|projects/[^/]+/roles|organizations/[0-9]+/roles)/[A-Za-z0-9_.]+$"
  re_folder_id  = "^(?:folders/)?[0-9]+$"
  re_org_id     = "^(?:organizations/)?[0-9]+$"
  re_member = join("|", [
    "^(?:user|group):[^@\\s]+@[^@\\s]+\\.[^@\\s]+$",
    "^serviceAccount:\\S+$", # includes GKE Workload Identity: PROJECT.svc.id.goog[NAMESPACE/KSA]
    "^domain:[^@\\s]+\\.[^@\\s]+$",
    "^principal(?:Set)?://iam\\.googleapis\\.com/\\S+$",
    "^ref:\\S+$",
  ])

  deletion_policies = ["DELETE", "PREVENT", "ABANDON"]
  public_principals = ["allUsers", "allAuthenticatedUsers"]
  principal_hint    = "use user:, group:, serviceAccount:, domain:, principal://, principalSet:// or ref:<account_id>"

  # --- Input source and top level ------------------------------------------------

  source_errors = compact([
    var.config_file == null && var.config_yaml == null ? "module input: set config_file (path to a YAML file) or config_yaml" : null,
    var.config_file != null && var.config_yaml != null ? "module input: set only one of config_file and config_yaml" : null,
  ])

  top_level_errors = concat(
    compact([
      local.raw != null && !can(keys(local.raw)) ? "(top level): the YAML must be a mapping with a service_accounts list" : null,
      local.top.project_id != null && local.file_project_id == null ? "(top level): project_id must be a string" : null,
      local.file_project_id != null && !can(regex(local.re_project_id, local.file_project_id)) ? "(top level): project_id ${jsonencode(local.file_project_id)} is not a valid project ID" : null,
      local.top.service_accounts != null && (can(keys(local.top.service_accounts)) || can(tostring(local.top.service_accounts))) ? "service_accounts: must be a list; start each service account with \"- account_id: ...\"" : null,
    ]),
    [
      for f in sort(try(keys(local.raw), [])) :
      "(top level): unknown key ${jsonencode(f)} (allowed: ${join(", ", keys(local.top_level_defaults))})"
      if !contains(keys(local.top_level_defaults), f)
    ],
  )

  # --- Service accounts ------------------------------------------------------------

  # GCP limits display_name and description in UTF-8 bytes, not characters.
  # Terraform has no byte-length function, but base64 reveals it exactly:
  # every 4 output characters encode 3 bytes, minus one per "=" of padding.
  sa_text_bytes = [
    for r in local.sa_records : {
      display_name = try(length(base64encode(r.display_name)) / 4 * 3 - length(regexall("=", base64encode(r.display_name))), 0)
      description  = try(length(base64encode(r.description)) / 4 * 3 - length(regexall("=", base64encode(r.description))), 0)
    }
  ]

  # One list of messages per service account, indexed like local.sa_raw.
  sa_errors = [
    for s in local.sa_raw : [
      for msg in(!s.is_map ? ["must be a mapping of service account fields (account_id, project_id, display_name, ...)"] : [
        length(s.unknown_fields) > 0 ? "unknown key(s) ${join(", ", [for f in s.unknown_fields : jsonencode(f)])} (allowed: ${join(", ", keys(local.sa_field_defaults))})" : null,

        s.fields.account_id == null ? "account_id is required" : null,
        s.fields.account_id != null && local.sa_records[s.index].account_id == null ? "account_id must be a string" : null,
        local.sa_records[s.index].account_id != null && !can(regex(local.re_account_id, local.sa_records[s.index].account_id)) ? "account_id ${jsonencode(local.sa_records[s.index].account_id)} must be 6-30 characters: a lowercase letter, then lowercase letters, digits or hyphens, not ending in a hyphen" : null,

        s.fields.project_id != null && local.sa_records[s.index].own_project_id == null ? "project_id must be a string" : null,
        local.sa_records[s.index].own_project_id != null && !can(regex(local.re_project_id, local.sa_records[s.index].own_project_id)) ? "project_id ${jsonencode(local.sa_records[s.index].own_project_id)} is not a valid project ID" : null,
        local.sa_records[s.index].project_id == null ? "no project: set project_id on the service account or at the top of the file, or pass the module's project_id variable" : null,

        s.fields.display_name != null && local.sa_records[s.index].display_name == null ? "display_name must be a string" : null,
        local.sa_text_bytes[s.index].display_name > 100 ? "display_name is ${local.sa_text_bytes[s.index].display_name} UTF-8 bytes; the maximum is 100" : null,
        s.fields.description != null && local.sa_records[s.index].description == null ? "description must be a string" : null,
        local.sa_text_bytes[s.index].description > 256 ? "description is ${local.sa_text_bytes[s.index].description} UTF-8 bytes; the maximum is 256" : null,

        s.fields.disabled != null && local.sa_records[s.index].disabled == null ? "disabled must be true or false" : null,
        s.fields.create_ignore_already_exists != null && local.sa_records[s.index].create_ignore_already_exists == null ? "create_ignore_already_exists must be true or false" : null,
        s.fields.deletion_policy != null && !contains(local.deletion_policies, coalesce(local.sa_records[s.index].deletion_policy, "-")) ? "deletion_policy ${jsonencode(s.fields.deletion_policy)} must be one of ${join(", ", local.deletion_policies)}" : null,

        s.fields.iam_bindings != null && (can(keys(s.fields.iam_bindings)) || can(tostring(s.fields.iam_bindings))) ? "iam_bindings must be a list" : null,
        s.fields.project_roles != null && (can(keys(s.fields.project_roles)) || can(tostring(s.fields.project_roles))) ? "project_roles must be a list" : null,
        s.fields.folder_roles != null && (can(keys(s.fields.folder_roles)) || can(tostring(s.fields.folder_roles))) ? "folder_roles must be a list" : null,
        s.fields.organization_roles != null && (can(keys(s.fields.organization_roles)) || can(tostring(s.fields.organization_roles))) ? "organization_roles must be a list" : null,
      ]) : "${local.sa_records[s.index].label}: ${msg}" if msg != null
    ]
  ]

  duplicate_account_id_errors = [
    for id, group in local.sa_by_account_id :
    "service_accounts: account_id ${jsonencode(id)} is defined ${length(group)} times (${join(", ", [for r in group : "service_accounts[${r.index}]"])}); each account_id may appear only once per file"
    if length(group) > 1
  ]

  # --- Role entries ------------------------------------------------------------------

  # One list of messages per role entry (principals included), indexed like local.entries.
  entry_errors = [
    for e in local.entries : concat([
      for msg in concat(
        # Shape of the entry itself.
        [
          e.kind == "iam_bindings" && !e.is_map ? "must be a mapping with role and members" : null,
          e.kind != "iam_bindings" && !e.is_map && !e.is_string ? "must be a role name or a mapping with role or roles" : null,
          e.is_map && length(e.unknown_fields) > 0 ? "unknown key(s) ${join(", ", [for f in e.unknown_fields : jsonencode(f)])} (allowed: ${join(", ", local.entry_kinds[e.kind].allowed_fields)})" : null,
        ],

        # role / roles.
        e.is_map ? [
          e.kind == "iam_bindings" && !e.has_role ? "role is required" : null,
          e.kind != "iam_bindings" && !e.has_role && !e.has_roles ? "set role or roles" : null,
          e.kind != "iam_bindings" && e.has_role && e.has_roles ? "set role or roles, not both" : null,
          e.kind != "iam_bindings" && e.has_roles && !e.roles_is_list ? "roles must be a list" : null,
          e.kind != "iam_bindings" && e.has_roles && e.roles_is_list && !e.has_role && length(e.roles) == 0 ? "roles must not be empty" : null,
        ] : [],
        [for r in e.roles : r == "" ? "roles must be non-empty strings" : "role ${jsonencode(r)} is not a valid role name (expected roles/NAME, projects/PROJECT/roles/NAME or organizations/ORG_ID/roles/NAME)" if !can(regex(local.re_role, r))],

        # Principals (iam_bindings only).
        e.kind == "iam_bindings" && e.is_map ? [
          !e.has_members ? "members is required (a list of principals)" : null,
          e.has_members && !e.members_is_list ? "members must be a list" : null,
          e.has_members && e.members_is_list && length(e.members) == 0 ? "members must not be empty" : null,
          e.has_authoritative && !e.authoritative_is_bool ? "authoritative must be true or false" : null,
        ] : [],

        # Grant targets.
        e.kind == "project_roles" && e.has_target && !can(regex(local.re_project_id, coalesce(e.target_raw, "-"))) ? ["project_id ${e.target_json} is not a valid project ID"] : [],
        e.kind == "folder_roles" && e.is_map && !e.has_target ? ["folder_id is required"] : [],
        e.kind == "folder_roles" && e.has_target && !can(regex(local.re_folder_id, coalesce(e.target_raw, "-"))) ? ["folder_id ${e.target_json} must be a numeric folder ID, optionally prefixed with folders/"] : [],
        e.kind == "organization_roles" && e.is_map && !e.has_target ? ["org_id is required"] : [],
        e.kind == "organization_roles" && e.has_target && !can(regex(local.re_org_id, coalesce(e.target_raw, "-"))) ? ["org_id ${e.target_json} must be a numeric organization ID, optionally prefixed with organizations/"] : [],

        # IAM condition.
        e.has_condition && !e.condition_is_map ? ["condition must be a mapping with title and expression"] : [],
        e.condition_is_map ? [
          length(e.condition_unknown) > 0 ? "unknown key(s) in condition: ${join(", ", [for f in e.condition_unknown : jsonencode(f)])} (allowed: ${join(", ", local.condition_fields)})" : null,
          try(e.condition.title, null) == null ? "condition.title is required" : null,
          try(e.condition.expression, null) == null ? "condition.expression is required" : null,
        ] : [],
      ) : "${e.path}: ${msg}" if msg != null
      ],
      [
        for j, m in e.members : format("%s.members[%d]: %s", e.path, j, (
          m == "" ? "must be a non-empty string" :
          contains(local.public_principals, m) ? "${m} is not allowed; public principals must never be able to use a service account" :
          !can(regex(local.re_member, m)) ? "${jsonencode(m)} is not a supported principal (${local.principal_hint})" :
          "${jsonencode(m)} does not match any account_id in this file"
        ))
        if e.kind == "iam_bindings" && (m == "" || !can(regex(local.re_member, m)) || (startswith(m, "ref:") && !can(local.service_accounts[trimprefix(m, "ref:")])))
      ],
    )
  ]

  # Service-account and entry messages, grouped per service account in file order.
  entry_errors_by_sa = { for i, e in local.entries : tostring(e.sa_index) => local.entry_errors[i]... }
  per_sa_errors = flatten([
    for s in local.sa_raw : [
      local.sa_errors[s.index],
      try(local.entry_errors_by_sa[tostring(s.index)], []),
    ]
  ])

  # --- Cross-entry conflicts -----------------------------------------------------------

  # A condition without a title is already reported above; skip the follow-on conflict.
  conflict_errors = concat(
    [
      for k, g in local.sa_iam_member_groups :
      "${join(", ", distinct([for r in g : r.path]))}: role ${g[0].role} for ${g[0].member} is granted more than once under condition title ${jsonencode(try(g[0].condition.title, ""))} with different condition contents; give each condition a unique title"
      if length(distinct([for r in g : jsonencode(r.condition)])) > 1 && alltrue([for r in g : r.condition == null || try(r.condition.title, null) != null])
    ],
    [
      for k, g in local.sa_iam_binding_groups :
      "${join(", ", distinct([for r in g : r.path]))}: role ${g[0].role} has more than one authoritative binding${g[0].condition == null ? "" : " with condition title ${jsonencode(try(g[0].condition.title, ""))}"}; merge their members into one entry"
      if length(distinct([for r in g : jsonencode({ members = r.members, condition = r.condition })])) > 1 && alltrue([for r in g : r.condition == null || try(r.condition.title, null) != null])
    ],
    [
      for k, g in local.resource_grant_groups :
      "${join(", ", distinct([for r in g : r.path]))}: role ${g[0].role} on ${try("${local.grant_scope_prefix[g[0].kind]}${g[0].target}", "the same target")} is granted more than once under condition title ${jsonencode(try(g[0].condition.title, ""))} with different condition contents; give each condition a unique title"
      if length(distinct([for r in g : jsonencode(r.condition)])) > 1 && alltrue([for r in g : r.condition == null || try(r.condition.title, null) != null])
    ],
    # The provider forbids mixing google_service_account_iam_binding and
    # google_service_account_iam_member for the same role on the same account.
    [
      for sa_role in distinct([for r in local.sa_iam_binding_records : "${r.sa_key}|${r.role}" if r.sa_key != null]) :
      "service account ${split("|", sa_role)[0]}: role ${split("|", sa_role)[1]} is granted both with authoritative: true and additively; an authoritative binding removes every member it does not list, so use one mode per role"
      if can(local.additive_sa_roles[sa_role])
    ],
  )
  additive_sa_roles = { for sa_role in distinct([for r in local.sa_iam_member_records : "${r.sa_key}|${r.role}" if r.sa_key != null]) : sa_role => true }

  errors = concat(
    local.source_errors,
    local.top_level_errors,
    local.duplicate_account_id_errors,
    local.per_sa_errors,
    local.conflict_errors,
  )
}
