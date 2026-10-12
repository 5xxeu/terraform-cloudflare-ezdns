# Checking Plans Before Apply

Part of the documentation of [ezdns](../README.md).

The module validates the records it is given, but it cannot see what a plan does to the records already in the state: a deleted or renamed YAML file, a changed name form or a removed module call deletes records, and the configuration is still valid. `tools/plan-guard.py` (Python 3.8 or later, no packages) reads a saved plan and fails when the plan deletes or replaces records, turns off the proxy of a record (which publishes its origin address), or leaves a required record set empty:

```sh
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
python3 tools/plan-guard.py tfplan.json --zone example.com --require @:MX --require @:A
terraform apply tfplan
```

A plan after the YAML file with the MX records was deleted, the address of `app` changed without a `key`, and `proxied` removed from `www`:

```console
$ python3 tools/plan-guard.py tfplan.json --zone example.com --require @:MX
The plan deletes 3 records (allowed: 0):
  module.dns.module.v5.cloudflare_dns_record.record["@ MX mx1.mail.example.net"]
  module.dns.module.v5.cloudflare_dns_record.record["@ MX mx2.mail.example.net"]
  module.dns.module.v5.cloudflare_dns_record.record["app A 192.0.2.10"]
The plan turns off the proxy of records, which publishes their origin address (--allow-proxy-disable allows it):
  module.dns.module.v5.cloudflare_dns_record.record["www CNAME"]
MX records of example.com: 0 after the apply, at least 1 required
$ echo $?
1
```

A plan without such changes prints `plan-guard: the plan passes` and exits with 0. In CI, run it between `plan` and `apply`:

```yaml
# GitHub Actions
- run: terraform plan -out=tfplan
- run: terraform show -json tfplan > tfplan.json
- run: python3 .terraform/modules/dns/tools/plan-guard.py tfplan.json --zone example.com --require @:MX
- run: terraform apply tfplan
```

With the module from the Terraform Registry or Git, `terraform init` puts the script into `.terraform/modules/<module name>/tools/`; with a [local copy](../README.md#local-copy), it is in `modules/ezdns/tools/` (full archive).

- `--max-deletes N` and `--max-replacements N` allow up to N deletions or replacements (default 0). A changed value without a `key` is a deletion and a creation, so it counts as a deletion.
- `--allow ADDRESS` leaves out the changes of resources whose address matches (`*` matches any characters, e.g. `--allow 'module.dns.*["www A *"]'`), for a change that was reviewed.
- `--allow-proxy-disable` allows turning off the proxy. Without it, the plan also fails when a proxied record is replaced, deleted, moved or loses its proxy (also one allowed by `--allow`) and an unproxied `A`, `AAAA` or `CNAME` record on its name publishes something new: it is created, moved there, or gets another type or content (a changed value without a `key`, another record type, a renamed record). An unproxied record that stays as it was (or changes in the same plan: deleted, moved, a new value, or the proxy turned on, as the order of the changes is not known) counts too when the name keeps no proxied `A`, `AAAA` or `CNAME` record that exists through the apply: while one is proxied, Cloudflare answers for the whole name (a new proxied record does not count, and neither does one that is replaced: Terraform deletes the old one first, unless the resource has `create_before_destroy`). A new unproxied `A`, `AAAA` or `CNAME` record with the value of a proxied record (an address, also written in another form, or a name), on any name and in any zone, counts as well: it publishes the origin that the proxy hides, for example when a rename drops the proxy. The plan also fails when a proxy status is not known until apply. Without `--zone`, the apex (`@`) is taken to match every name, as the script cannot tell `@` from the zone name.
- `--require NAME:TYPE[:MIN]` requires at least MIN records (default 1) of a type on a name after the apply, with names as in `records` and `--zone` to qualify them. When the plan has records of several zones, give `--zone-id ID` to count the records of one zone; `--zone` then qualifies only the names of that zone, and the names of the other zones are compared without it. When the zone of records is known only after apply (a zone created in the same plan), `--require` fails, as such zones cannot be told apart: apply the zone first.
- `--module module.dns` checks only the records of one module call, with all its instances when it has `count` or `for_each` (`module.dns[0]`, `module.dns["prod"]`); `--module 'module.dns["prod"]'` checks one instance. A record moved out of the module by a `moved` block is still checked. Records of other module calls on the same names still count for the proxy check, as the proxy hides a whole name.

Apply the checked plan file (`terraform apply tfplan`), not a new plan: a new plan can differ from the checked one. The script checks `cloudflare_dns_record` and `cloudflare_record` resources of any configuration, also outside the module. Exit status 1 means the plan has changes that are not allowed, 2 that the plan cannot be read, has an unexpected structure or the arguments are wrong.
