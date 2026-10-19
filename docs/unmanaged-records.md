# Records Not in the Configuration

Part of the documentation of [ezdns](../README.md).

With `report_unmanaged = true` (provider v5), the module reads the records of all types in the zone and lists those that no configured record matches, in the `unmanaged_records` output (`id`, `name`, `type`, `content`, `priority`, `data`) and in a `plan` warning. The warning shows the type, name and ID only (the first 50 records), and the output is sensitive: the content of a proxied record is the origin address that Cloudflare hides from DNS, and plans often end up in CI logs. Records are compared like in [import](importing.md#importing-existing-records); a configured `MX` or `URI` record describes the records of its priority (an `MX 20` next to the configured `MX 10` is listed). When a value changes, the record with the old value matches nothing, but it is in the state, not unmanaged. The module cannot see the state, so on a name and type where the records without a match are no more than the configured records without one (records with a new value, a new priority or new records), it takes them as the old values and leaves them out: a new address of `app` (or an `MX 20` instead of the configured `MX 10`) is not listed, while a second record next to it is, together with the old one. A record added by hand on the name and type of a new record is therefore listed from the plan after the one that creates the new record. Without `import_existing`, the warning also lists configured records that match several records in the zone (copies of the same record, or a record described too loosely, such as a structured record without a field that tells two records apart), with type, name and IDs; with it, they stop the plan. The warning shows on `plan` and on `apply` while `report_unmanaged` is set. Nothing is deleted: Terraform can only delete records that are in its state, and deleting records outside it could remove the records of other tools (see [Next to external-dns](recipes.md#next-to-external-dns)). For each listed record, add it to `records` and adopt it with an `import` block (`import_existing` gives the import IDs, see [Importing Existing Records](importing.md#importing-existing-records)), or delete it yourself.

To read the values, pass the output through in the root module and read it from a saved plan (`terraform output` only shows the state of the last `apply`):

```hcl
module "dns" {
  source           = "5xxeu/ezdns/cloudflare"
  version          = "2.16.4"
  zone_id          = var.zone_id
  report_unmanaged = true
  records          = { "@" = { A = [{ content = "192.0.2.1" }] } }
}

output "unmanaged_records" {
  value     = module.dns.unmanaged_records
  sensitive = true
}
```

The plan warns with the type, name and ID of each record:

```text
Warning: Check block assertion failed

The zone has 2 records that the configuration does not describe (records of
other tools, such as external-dns, are listed too). Add them to records and
adopt them with import blocks (import_existing gives their IDs), or delete
them yourself. Their values are in the sensitive unmanaged_records output:
pass it through as a root module output, then terraform plan -out=tfplan
and terraform show -json tfplan:
A old.example.com (372e67954025e0ba6aaa6d586b9e0b59)
TXT example.com (9a7806061c88ada191ed06f989cc3dac)
```

```console
$ terraform plan -out=tfplan
$ terraform show -json tfplan | jq '.planned_values.outputs.unmanaged_records.value'
[
  {
    "content": "192.0.2.9",
    "data": null,
    "id": "372e67954025e0ba6aaa6d586b9e0b59",
    "name": "old.example.com",
    "priority": null,
    "type": "A"
  },
  {
    "content": "google-site-verification=abc",
    "data": null,
    "id": "9a7806061c88ada191ed06f989cc3dac",
    "name": "example.com",
    "priority": null,
    "type": "TXT"
  }
]
```

The report needs the `DNS Read` permission and makes one lookup per record type (21) on every plan, and the provider reads the records of a type in pages, so a large zone takes more requests. Turn it on when reviewing the zone or in a scheduled CI job rather than on every plan. Like the import, a lookup that returns 100,000 records of one type (the limit) stops the plan, since the report would be incomplete. Records that Cloudflare manages itself and does not return as DNS records (the zone's own name servers) are not listed.

Records that are expected in the zone can be left out of the report with `unmanaged_ignore`: a record is left out when it matches all fields of an entry, `name_regex` (RE2, matched against the fully qualified name in lower case without a trailing dot; unanchored, so use `^` and `$`) and `types`:

```hcl
unmanaged_ignore = [
  { name_regex = "^_acme-challenge\\.", types = ["TXT"] }, # cert-manager
  { types = ["NS"], name_regex = "^dev\\.example\\.com$" }, # a delegation managed elsewhere
]
```

With `unmanaged_policy = "error"`, the report stops the plan instead of showing a warning, with the same list and the line `unmanaged_policy is "error", so the plan stops.` Use it in CI for a zone (or the [part of a zone](#the-part-of-the-zone-a-module-call-owns)) that only this configuration may change: a record added by hand in the dashboard then fails the next plan until it is added to the configuration or deleted.

## The Part of the Zone a Module Call Owns

When several teams or tools share a zone, `owned_names` limits a module call to its part of it: the names in `include` and below them, except the names in `exclude` and below them. Names are written like in `records` and compared fully qualified, case-insensitively and by whole labels, so `apps` covers `web.apps` but not `myapps`:

```hcl
owned_names = {
  include = ["apps"]     # apps.example.com and everything below it
  exclude = ["k8s.apps"] # except the part that external-dns manages
}
```

- A configured record outside this part fails at `plan`, with the name and where the record is defined. A typo in a name cannot create a record in the part of another team:

  ```text
  Error: Module output value precondition failed

  These records are outside owned_names (included: apps.example.com; excluded:
  k8s.apps.example.com), the part of the zone that this module call manages:
  "api.k8s.apps.example.com" (A) from records["api.k8s.apps"]["A"][0]
  "app.example.com" (A) from records["app"]["A"][0]
  ```
- [`report_unmanaged`](#records-not-in-the-configuration) only looks at this part: records of other teams and tools are not reported as unmanaged.
- `owned_names` is a rule of the configuration, not a lock: another tool can still write into this part of the zone. `null` (the default) is the whole zone.
