# Invariants over all records, reported by the preconditions of output.flat_records
# (outputs.tf): they compare records with each other or with other inputs, which
# validations of var.records cannot do on Terraform 1.8.

locals {
  # The same record written in different forms gets different keys, so it is checked
  # separately: names in different forms ("www" and "www.example.com", "@" and the zone
  # name), and values that the import takes for one record (import.tf: hostnames in any
  # case and with or without the trailing dot, TXT text quoted or not, numbers in data
  # as numbers, HTTPS service parameters as fields or in value). Records with an
  # explicit key are compared by their keys. Long values and data are shown as a hash
  by_identity = {
    for r in local.records : "${r.fqdn} ${r.explicit_key != null ? r.explicit_key : "${r.type} ${(
      r.data != null || contains(["TXT", "OPENPGPKEY"], r.type) ? substr(sha1(local.configured_value[r.key]), 0, 12) : local.configured_value[r.key]
    )}"}" => r...
  }

  duplicates = concat(
    [
      for key, group in local.grouped : "\"${key}\" from ${join(" and ", [for r in group : r.source])}"
      if length(group) > 1
    ],
    [
      for identity, group in local.by_identity : "\"${identity}\" as ${join(" and ", [for r in group : "\"${r.key}\" from ${r.source}"])}"
      if length(distinct([for r in group : r.key])) > 1
    ],
  )

  # A CNAME cannot share its name with other records, except at the zone apex (CNAME
  # flattening: MX, TXT and others, but not A or AAAA, which Cloudflare rejects there
  # too) and on names listed in allowed_cname_conflicts (existing zones, where
  # Cloudflare accepted it for records that are not proxied). A name never has more
  # than one CNAME, whatever keys the records have. Names are grouped fully qualified.
  by_name = { for r in local.records : r.fqdn => r... }
  cname_shared = [
    for name, group in local.by_name : name
    if anytrue([for r in group : r.type == "CNAME"]) && anytrue([
      for r in group : name == lower(local.zone) ? contains(["A", "AAAA"], r.type) : r.type != "CNAME"
    ])
  ]
  allowed_cname_conflicts = distinct([for n in var.allowed_cname_conflicts : local.fqdn[n]])
  # Looked up by name: contains() reads its whole list on every call, which is
  # quadratic over the names of a large zone
  cname_shared_names  = { for n in local.cname_shared : n => true }
  allowed_cname_names = { for n in local.allowed_cname_conflicts : n => true }
  cname_conflicts = [
    for name, group in local.by_name : "\"${name}\": ${join(", ", [for r in group : "${r.type} from ${r.source}"])}"
    if length([for r in group : r if r.type == "CNAME"]) > 1
    || (lookup(local.cname_shared_names, name, false) && !lookup(local.allowed_cname_names, name, false))
  ]
  # TTLs below minimum_ttl (records that are not proxied; 1 means automatic), and a
  # default_ttl below it even when no record uses it. The plan is not known here, so a
  # zone on Enterprise opts in with minimum_ttl = 30
  low_ttls = concat(
    var.default_ttl != 1 && var.default_ttl < var.minimum_ttl ? ["default_ttl (${var.default_ttl})"] : [],
    [
      for r in local.records : "\"${r.key}\" (ttl ${r.ttl}) from ${r.source}"
      if !r.proxied && r.ttl != 1 && r.ttl < var.minimum_ttl
    ],
  )

  # A wildcard is only valid as the whole leftmost label. Names, prefixes and aliases
  # are checked on their own in the records validation; this checks the names they
  # combine into ("_acme-challenge" under "*" gives "_acme-challenge.*") and the
  # targets of inline aliases ("cdn.ALIASES" under "*.app" gives "cdn.*.app")
  combined_names = concat(
    [for i, e in local.entries : { name = local.entry_names[i], source = e.source }],
    [
      for e in local.entries : { name = "${e.prefix}.${e.base_name == "@" ? local.zone : e.base_name}", source = "${e.source} (alias target)" }
      if e.kind == "ALIASES" && e.prefix != null
    ],
  )
  misplaced_wildcards = [
    for n in local.combined_names : "\"${n.name}\" from ${n.source}"
    if n.name != "*" && !can(regex("^(\\*\\.)?[^*]*$", n.name))
  ]

  # Each part of a name is checked on its own in the records validation; the name
  # they combine into with the zone must still fit into 253 characters. The same goes
  # for the targets that ALIASES build from a prefix and a name (CNAME targets written
  # in the configuration are limited by the validation already)
  long_names = distinct(concat(
    [
      for r in local.records : "\"${r.fqdn}\" (${length(r.fqdn)} characters) from ${r.source}"
      if length(r.fqdn) > 253
    ],
    [
      for r in local.records : "\"${trimsuffix(r.content, ".")}\" (${length(trimsuffix(r.content, "."))} characters), the target of \"${r.key}\" from ${r.source}"
      if r.type == "CNAME" && length(trimsuffix(r.content == null ? "" : r.content, ".")) > 253
    ],
  ))

  # A CNAME pointing to its own name is a loop. Targets are compared like names: case,
  # a trailing dot and the short form ("www" on www.example.com) do not matter, and "@"
  # is the zone name in content already
  self_cnames = [
    for r in local.records : "\"${r.key}\" from ${r.source}"
    # Terraform 1.8 evaluates both sides of &&, and records of other types may have no content
    if r.type == "CNAME" && contains([
      lower(trimsuffix((r.content == null ? "" : r.content), ".")),
      "${lower(trimsuffix((r.content == null ? "" : r.content), "."))}.${lower(local.zone)}",
    ], r.fqdn)
  ]

  # Listed names that no longer have a conflict, so the list does not keep growing
  unused_allowed_cname_conflicts = [for n in local.allowed_cname_conflicts : n if !lookup(local.cname_shared_names, n, false)]
}

# owned_names: the part of the zone this module call manages, by whole labels. A name is
# owned when it is an included name or below one, and neither an excluded name nor below
# one
locals {
  owned_include = var.owned_names == null ? [lower(local.zone)] : distinct([for n in var.owned_names.include : local.fqdn[n]])
  owned_exclude = var.owned_names == null ? [] : distinct([for n in var.owned_names.exclude : local.fqdn[n]])

  not_owned = [
    for r in local.records : "\"${r.fqdn}\" (${r.type}) from ${r.source}"
    if !(
      anytrue([for o in local.owned_include : r.fqdn == o || endswith(r.fqdn, ".${o}")])
      && !anytrue([for o in local.owned_exclude : r.fqdn == o || endswith(r.fqdn, ".${o}")])
    )
  ]
}

check "allowed_cname_conflicts_in_use" {
  assert {
    condition     = length(local.unused_allowed_cname_conflicts) == 0
    error_message = "allowed_cname_conflicts lists names without a CNAME conflict, which can be removed: ${join(", ", local.unused_allowed_cname_conflicts)}"
  }
}

# Two SPF records on one name are a permanent error for every receiver (RFC 7208,
# section 3.2), and several DMARC records mean no policy at all (RFC 7489, section
# 6.6.3); Cloudflare accepts both. Only a warning: zones that have it still plan. The
# text of TXT values is compared as the import does (quoted chunks joined)
locals {
  policy_texts = {
    for key, rec in local.flat_records : key => jsondecode(local.configured_txt[key]).value
    if rec.type == "TXT"
  }
  spf_names = {
    for key, text in local.policy_texts : local.flat_records[key].fqdn => text...
    if can(regex("(?i)^v=spf1( |$)", text))
  }
  dmarc_names = {
    for key, text in local.policy_texts : local.flat_records[key].fqdn => text...
    if startswith(local.flat_records[key].fqdn, "_dmarc.") && can(regex("(?i)^v=DMARC1[ ]*(;|$)", text))
  }
  repeated_policies = concat(
    # Different texts only: the same record twice fails as a duplicate
    [for name, texts in local.spf_names : "${name}: ${length(distinct(texts))} SPF records (v=spf1)" if length(distinct(texts)) > 1],
    [for name, texts in local.dmarc_names : "${name}: ${length(distinct(texts))} DMARC records (v=DMARC1)" if length(distinct(texts)) > 1],
  )
}

check "records_one_spf_and_dmarc_per_name" {
  assert {
    condition     = length(local.repeated_policies) == 0
    error_message = "A name can have one SPF record and one DMARC record: with two SPF records every receiver fails the SPF check (RFC 7208), with two DMARC records the domain has no DMARC policy (RFC 7489). Merge them into one record:\n${join("\n", local.repeated_policies)}"
  }
}

# A null MX ("." with priority 0) says that a name takes no mail, and a name with a null
# MX must have no other MX record (RFC 7505, section 3); Cloudflare accepts both. Only a
# warning, like the SPF and DMARC check: zones that have it still plan
locals {
  mx_targets = { for key, rec in local.flat_records : rec.fqdn => rec.content... if rec.type == "MX" }
  null_mx_with_others = [
    for name, targets in local.mx_targets : "${name}: a null MX and ${length([for t in targets : t if t != "."])} other MX records"
    if anytrue([for t in targets : t == "."]) && length([for t in targets : t if t != "."]) > 0
  ]
}

check "records_null_mx_alone" {
  assert {
    condition     = length(local.null_mx_with_others) == 0
    error_message = "A name with a null MX (content \".\", RFC 7505) takes no mail and must have no other MX record; senders may still try the other records. Remove the null MX, or the other MX records:\n${join("\n", local.null_mx_with_others)}"
  }
}
