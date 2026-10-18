# Matching of records that already exist in the zone to the configured records,
# so they can be adopted with import blocks instead of being created again

locals {
  # Names, hostnames and hex values are compared case-insensitively and without a
  # trailing dot, numbers in data as numbers, other values exactly. OPENPGPKEY content is base64, so it is
  # compared exactly.
  #
  # Cloudflare stores TXT content as it was sent, and v=spf1 "a" -all and
  # "v=spf1 \"a\" -all" are the same DNS record. A value in the zone file form
  # (one or more quoted chunks, "a" "b", with no escapes other than \" and \\) is
  # compared as its chunks joined and unescaped; a value without a leading quote is
  # literal text, compared as written, so prefix" "suffix is not prefixsuffix. A value
  # with a leading quote that is not in that form (such as "\065", where \065 is a
  # decimal escape, "A" in zone files) is opaque: it only matches the same text, never
  # a decoded value. The comparison value is the pair, as JSON.
  txt_zone_file_form = "^\"(?:[^\"\\\\]|\\\\[\"\\\\])*\"(?:[ \\t]+\"(?:[^\"\\\\]|\\\\[\"\\\\])*\")*$"
  txt_chunk          = "\"((?:[^\"\\\\]|\\\\[\"\\\\])*)\""
  existing_txt = {
    for r in var.existing_records : r.id => (
      r.content == null ? "" :
      can(regex(local.txt_zone_file_form, r.content))
      ? jsonencode({ opaque = false, value = replace(join("", [for chunk in regexall(local.txt_chunk, r.content) : chunk[0]]), "/\\\\([\"\\\\])/", "$1") })
      : jsonencode({ opaque = startswith(r.content, "\""), value = r.content })
    )
  }
  existing = [
    for r in var.existing_records : {
      id   = r.id
      name = lower(trimsuffix(r.name, "."))
      type = r.type
      content = r.content == null ? null : (
        r.type == "TXT" ? local.existing_txt[r.id] :
        contains(local.exact_content_types, r.type) ? r.content :
        r.type == "AAAA" && can(cidrhost("${r.content}/128", 0)) ? (strcontains(cidrhost("${r.content}/128", 0), ":") ? cidrhost("${r.content}/128", 0) : "::ffff:${cidrhost("${r.content}/128", 0)}") :
        lower(trimsuffix(r.content, "."))
      )
      priority = r.priority
      data = {
        for field, value in coalesce(r.data, {}) : field => (
          contains(lookup(local.numeric_fields, r.type, []), field) && can(tonumber(value)) ? tostring(tonumber(value)) :
          (contains(local.case_insensitive_fields, field) && !(field == "target" && r.type == "URI")) || (field == "certificate" && contains(["TLSA", "SMIMEA"], r.type)) ? lower(trimsuffix(value, ".")) :
          r.type == "CAA" && field == "value" && contains(local.caa_issuer_tags, lookup(r.data, "tag", "")) ? format("%s%s", lower(trimsuffix(trimspace(split(";", value)[0]), ".")), substr(value, length(split(";", value)[0]), -1)) :
          value
        )
      }
    }
  ]

  # Record types whose content is not a hostname or an address
  exact_content_types = ["OPENPGPKEY"]

  # Fields of structured records that hold hostnames or hex strings (the target of a
  # URI record is a URI, compared exactly: paths and queries are case-sensitive)
  case_insensitive_fields = ["target", "replacement", "digest", "fingerprint"]

  # CAA issue/issuewild values are "<issuer domain>[; parameters]": the domain is
  # compared like a hostname, the parameters (account URIs, ...) exactly
  caa_issuer_tags = ["issue", "issuewild"]

  # Data fields that hold numbers, compared as numbers ("5060.0" is 5060; Cloudflare
  # returns numbers). The fields of the range validation of records
  numeric_fields = {
    SRV    = ["priority", "weight", "port"]
    URI    = ["weight"]
    HTTPS  = ["priority"]
    SVCB   = ["priority"]
    TLSA   = ["usage", "selector", "matching_type"]
    SMIMEA = ["usage", "selector", "matching_type"]
    SSHFP  = ["algorithm", "type"]
    DS     = ["key_tag", "algorithm", "digest_type"]
    DNSKEY = ["flags", "protocol", "algorithm"]
    CERT   = ["type", "key_tag", "algorithm"]
    NAPTR  = ["order", "preference"]
    CAA    = ["flags"]
    LOC = [
      "lat_degrees", "lat_minutes", "lat_seconds", "long_degrees", "long_minutes", "long_seconds",
      "altitude", "size", "precision_horz", "precision_vert",
    ]
  }

  # The data of the configured records in the form of the existing ones above
  configured_data = {
    for key, rec in local.flat_records : key => {
      for field, value in rec.data : field => (
        contains(lookup(local.numeric_fields, rec.type, []), field) && can(tonumber(value)) ? tostring(tonumber(value)) :
        (contains(local.case_insensitive_fields, field) && !(field == "target" && rec.type == "URI")) || (field == "certificate" && contains(["TLSA", "SMIMEA"], rec.type)) ? lower(trimsuffix(value, ".")) :
        rec.type == "CAA" && field == "value" && contains(local.caa_issuer_tags, lookup(rec.data, "tag", "")) ? format("%s%s", lower(trimsuffix(trimspace(split(";", value)[0]), ".")), substr(value, length(split(";", value)[0]), -1)) :
        value
      )
    } if rec.data != null
  }

  # The value that the import compares, per configured record: the data, the TXT text
  # or the content. Records with the same name, type and value are one DNS record
  configured_value = {
    for key, rec in local.flat_records : key => (
      rec.data != null ? jsonencode(local.configured_data[key]) :
      rec.type == "TXT" ? local.configured_txt[key] :
      contains(local.exact_content_types, rec.type) ? rec.content :
      lower(trimsuffix(rec.content, "."))
    )
  }

  configured_txt = {
    for key, rec in local.flat_records : key => (
      can(regex(local.txt_zone_file_form, rec.content))
      ? jsonencode({ opaque = false, value = replace(join("", [for chunk in regexall(local.txt_chunk, rec.content) : chunk[0]]), "/\\\\([\"\\\\])/", "$1") })
      : jsonencode({ opaque = startswith(rec.content, "\""), value = rec.content })
    )
    if rec.type == "TXT"
  }

  # Existing records grouped by type and name, so each configured record is compared
  # only with the records of its own name and type (not every record of the zone)
  existing_by_name = { for e in local.existing : "${e.type} ${e.name}" => e... }

  # Records with ignore_changes are matched by name and type instead (live.tf)
  import_matches = {
    for key, rec in local.flat_records : key => [
      for e in try(local.existing_by_name["${rec.type} ${rec.fqdn}"], []) : e.id
      if rec.data == null
      ? e.content == local.configured_value[key]
      : alltrue([for field, value in local.configured_data[key] : lookup(e.data, field, "") == value])
    ] if length(rec.ignore_changes) == 0
  }

  # Configured records with a priority (MX, URI) that match several existing records
  # take the one with the same priority (a zone with MX 10 and MX 20 on one host).
  # Without such a record, or with several, the matches stay ambiguous
  existing_priority = { for e in local.existing : e.id => e.priority }
  narrowed_matches = {
    for key, ids in local.import_matches : key => (
      length(ids) > 1 && local.flat_records[key].priority != null
      && length([for id in ids : id if local.existing_priority[id] == local.flat_records[key].priority]) == 1
      ? [for id in ids : id if local.existing_priority[id] == local.flat_records[key].priority]
      : ids
    )
  }

  # Only unambiguous matches: records with no match are new, records with several
  # matches (duplicates in the zone) are not imported, and the plan stops on them
  single_matches = {
    for key, ids in local.narrowed_matches : key => ids[0]
    if length(ids) == 1
  }

  # An existing record can be imported into one address only. Configured records that
  # differ only in priority (MX, URI) match the same existing record: the one with the
  # same priority gets it, and the others are new records. Without such a record, or
  # with several, none of them is imported.
  claims = { for key, id in local.single_matches : id => key... }
  claim_winners = {
    for id, keys in local.claims : id => (
      length(keys) == 1 ? keys : [
        for key in keys : key
        if local.flat_records[key].priority != null && local.existing_priority[id] != null && local.flat_records[key].priority == local.existing_priority[id]
      ]
    )
  }
  matched_record_ids = {
    for id, keys in local.claim_winners : keys[0] => id
    if length(keys) == 1
  }
  matched_duplicates = merge(
    { for key, ids in local.narrowed_matches : key => ids if length(ids) > 1 },
    {
      for claim in flatten([
        for id, keys in local.claims : [for key in keys : { key = key, id = id }]
        if length(local.claim_winners[id]) != 1
      ]) : claim.key => [claim.id]
    },
  )

  # Without import_existing, the existing records are only reported (unmanaged
  # records), so nothing is imported and an ambiguous match does not stop the plan
  import_record_ids = merge(
    # An ID that a record with ignore_changes takes is not imported a second time
    { for key, id in local.matched_record_ids : key => id if var.import_existing && !lookup(local.live_id_names, id, false) },
    { for key, r in local.live_records : key => r.id if var.import_existing && r != null },
  )
  import_duplicates = { for key, ids in local.matched_duplicates : key => ids if var.import_existing }

  # Existing records that no configured record matches: records in the zone that the
  # configuration does not describe. For the report, an MX or URI record describes only
  # the existing records of its priority (MX 20 next to the configured MX 10 is
  # unmanaged; MX 20 instead of it is its old priority, see previous_value_ids); an
  # existing record without a known priority still matches. SRV keeps its priority in
  # data, compared already
  report_matches = {
    for key, ids in local.import_matches : key => (
      contains(["MX", "URI"], local.flat_records[key].type) && local.flat_records[key].priority != null
      ? [for id in ids : id if local.existing_priority[id] == null || local.existing_priority[id] == local.flat_records[key].priority]
      : ids
    )
  }
  # Maps of IDs rather than sets, read by index: contains() and lookup() walk the whole
  # collection on every call, so a test per existing record would grow quadratically
  # The live records of records with ignore_changes are managed too
  matched_ids = { for id in concat(flatten(values(local.report_matches)), tolist(local.live_ids)) : id => true... }

  # A configured record that matches no existing record is new or gets a new value (or
  # priority) in this apply, and the existing record with its old value then matches
  # nothing either: it is in the state, not unmanaged. The state is not known here, so
  # on a name and type where the existing records without a match are no more than the
  # configured records without one, they are taken as the old values and left out of
  # the report. A record added by hand next to a new record is then reported only from
  # the next plan on, once the new record exists
  unmatched_configured = {
    for key, ids in local.report_matches : "${local.flat_records[key].type} ${local.flat_records[key].fqdn}" => key...
    if length(ids) == 0
  }
  unmatched_existing = {
    for e in local.existing : "${e.type} ${e.name}" => e.id...
    if !can(local.matched_ids[e.id])
  }
  previous_value_ids = {
    for id in flatten([
      for group, ids in local.unmatched_existing : ids
      if length(ids) <= length(try(local.unmatched_configured[group], []))
    ]) : id => true
  }

  # Configured records that several existing records match (copies of one record) for
  # the report: type, name and IDs only, since record keys may contain origin
  # addresses
  report_ambiguous = {
    for key, ids in local.report_matches : key => {
      type = local.flat_records[key].type
      name = local.flat_records[key].fqdn
      ids  = ids
    } if length(ids) > 1
  }
  # Only records in owned_names are reported, and none that unmanaged_ignore expects
  reported = {
    for e in local.existing : e.id => (
      anytrue([for o in local.owned_include : e.name == o || endswith(e.name, ".${o}")])
      && !anytrue([for o in local.owned_exclude : e.name == o || endswith(e.name, ".${o}")])
      && !anytrue([
        for i in var.unmanaged_ignore : (i.name_regex == null ? true : length(regexall(i.name_regex, e.name)) > 0) && (i.types == null ? true : contains(coalesce(i.types, []), e.type))
      ])
    )
  }
  unmanaged_records = [
    for r in var.existing_records : {
      id       = r.id
      name     = r.name
      type     = r.type
      content  = r.content
      priority = r.priority
      data     = r.data
    }
    if !can(local.matched_ids[r.id]) && !can(local.previous_value_ids[r.id]) && local.reported[r.id]
  ]
}
