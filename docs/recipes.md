# Recipes

Part of the documentation of [ezdns](../README.md).

## A Record Type or Field the Module Does Not Support

Record types and attributes are a closed list, so misspelled ones fail at `plan`. When Cloudflare adds something the module does not know yet, manage that record with the provider resource next to the module call, in the same zone:

```hcl
resource "cloudflare_dns_record" "special" {
  zone_id = var.zone_id
  name    = "special"
  type    = "TXT"
  content = "..."
  ttl     = 1
  # any argument the provider supports
}
```

Keep it out of `records`, so the record is not managed twice. Once the module supports it, move it into `records` with a `moved` block to its key.

Mail with SPF, DKIM and DMARC; the DKIM record has a `key`, so rotating the key updates the record in place:

```hcl
"@" = {
  MX = [
    { content = "mx1.mail.example.net", priority = 10 },
    { content = "mx2.mail.example.net", priority = 20 },
  ]
  TXT = [{ content = "v=spf1 include:_spf.mail.example.net -all" }]

  "google._domainkey.TXT" = [
    { key = "dkim", content = "v=DKIM1; k=rsa; p=MIIBIjANBg..." },
  ]
  "_dmarc.TXT" = [
    { content = "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com" },
  ]
}
```

A website behind the Cloudflare proxy, with `www` pointing to the apex:

```hcl
"@" = {
  A       = [{ content = "192.0.2.10", proxied = true }]
  ALIASES = [{ content = "www", proxied = true }]
}
```

Certificate authority restrictions and the ACME DNS challenge of a certificate for `app.example.com`:

```hcl
"@" = {
  CAA = [
    { content = "letsencrypt.org", tag = "issue" },
    { content = "letsencrypt.org", tag = "issuewild" },
    { content = "mailto:security@example.com", tag = "iodef" },
  ]
}
"app" = {
  A                     = [{ content = "192.0.2.30" }]
  "_acme-challenge.TXT" = [{ key = "acme", content = "challenge-token" }]
}
```

A service advertised with SRV:

```hcl
"_sip._tcp" = {
  SRV = [{
    data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" }
  }]
}
```

## Next to external-dns

The module manages only the records in its configuration and leaves the others alone, so a controller such as [external-dns](https://github.com/kubernetes-sigs/external-dns) can manage records of the same zone, for example for Kubernetes ingresses. Give each its own names, so they never write the same record:

- Let external-dns manage a subdomain (`--domain-filter=k8s.example.com`), or restrict it to annotated resources, and keep those names out of `records`.
- external-dns keeps a TXT ownership record next to each record it manages (`--txt-owner-id`, `--txt-prefix`); leave these to it as well. A `CNAME` in `records` on a name that external-dns also uses fails at apply, and two tools writing the same `A` record overwrite each other.
- With [`report_unmanaged`](unmanaged-records.md#records-not-in-the-configuration), the records of external-dns show up as unmanaged. Leave its part of the zone out of [`owned_names`](unmanaged-records.md#the-part-of-the-zone-a-module-call-owns), so that the module cannot write there and the report does not look there, and leave its TXT ownership records on shared names out of the report with `unmanaged_ignore`:

  ```hcl
  owned_names      = { include = ["@"], exclude = ["k8s"] }
  unmanaged_ignore = [{ name_regex = "^extdns-", types = ["TXT"] }] # --txt-prefix=extdns-
  ```

## Internationalized Names

The module expects internationalized names in Punycode, as the Cloudflare API does. The `idna` submodule takes them in Unicode instead: it converts them with `provider::idna::to_ascii` of the [`5xxeu/idna`](https://registry.terraform.io/providers/5xxeu/idna/latest) provider and passes everything to the v5 wrapper. The provider has only functions (Terraform 1.8 or later): no configuration and no network requests, but `terraform init` installs it, which is why the root module does not use it.

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare//modules/dns/idna"
  version = "2.14.0"

  zone_id   = var.zone_id
  zone_name = "münchen.de" # or null: the zone is looked up and its name converted
  records = {
    "@"      = { A = [{ content = "192.0.2.1" }], MX = [{ content = "mx.münchen.de", priority = 10 }] }
    "bücher" = { CNAME = [{ content = "www.münchen.de" }] }
  }
}
```

The plan shows the converted names, which are also in the record keys:

```text
  # module.dns.module.v5.cloudflare_dns_record.record["@ A 192.0.2.1"] will be created
  # module.dns.module.v5.cloudflare_dns_record.record["@ MX mx.xn--mnchen-3ya.de"] will be created
  # module.dns.module.v5.cloudflare_dns_record.record["xn--bcher-kva CNAME"] will be created
```

- It has the inputs and outputs of the root module. `zone_name`, names, prefixes of record types (`"straße.A"`), `ALIASES`, the `content` of `CNAME`, `MX`, `NS` and `PTR` records, `target` of `SRV`, `HTTPS` and `SVCB` and `replacement` of `NAPTR` in `data`, the host of a `URI` target, `allowed_cname_conflicts` and `owned_names` are converted, in `records` and in `record_groups`. Other values (TXT content, comments) stay as written.
- Only values with non-ASCII characters are converted. Record keys contain the converted form (`xn--bcher-kva CNAME`), the same as for names written in Punycode in lower case, and names in ASCII keep their keys as written, so a configuration can switch to Unicode names without changing addresses in the state.
- Its module call inside is named `v5`, like in the root module, so the records have the same addresses (`module.dns.module.v5.cloudflare_dns_record.record[...]`): switching `source` between the root module and `//modules/dns/idna` needs no `moved` blocks. Run `terraform init -upgrade` and check that the plan shows no changes.
- Errors show the converted names (`records["xn--bcher-kva"]["A"][0]`). A name written in both forms (`bücher` and `xn--bcher-kva`) is the same name, and the same record under both fails as a duplicate.

Without the submodule, the same provider converts names in the configuration of the module call:

```hcl
terraform {
  required_providers {
    idna = {
      source  = "5xxeu/idna"
      version = "~> 0.1"
    }
  }
}

locals {
  records = {
    "@"      = { A = [{ content = "192.0.2.1" }] }
    "bücher" = { CNAME = [{ content = provider::idna::to_ascii("www.münchen.de") }] }
  }
}

module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.14.0"

  zone_id   = var.zone_id
  zone_name = provider::idna::to_ascii("münchen.de")
  records   = { for name, types in local.records : provider::idna::to_ascii(name) => types }
}
```

- An internationalized zone must set `zone_name` here, see [Requirements](../README.md#requirements).
- `to_ascii` keeps `@`, a `*` wildcard and labels such as `_acme-challenge`, so it can convert every name. Convert the names, but not the record types under them: `to_ascii` would write `"_acme-challenge.TXT"` in lower case. An internationalized prefix of a type is converted on its own (`"${provider::idna::to_ascii("straße")}.A"`). Convert targets where they are written: `content` of `CNAME`, `MX`, `NS`, `PTR` and `ALIASES`, `target` of `SRV`, `HTTPS` and `SVCB` and `replacement` of `NAPTR` in `data`. A `URI` target is a URI: convert only its host (`"https://${provider::idna::to_ascii("münchen.de")}/path"`).
- Record keys contain the converted form (`xn--bcher-kva CNAME`). A configuration that wrote these names and targets in Punycode in lower case can switch to the readable form without changing addresses in the state. Keys keep a name as written, so a name written in another form (`XN--BCHER-KVA`) gets a new key: keep the record with a `moved` block, see [Record Keys](../README.md#record-keys).
- With records in YAML, convert the names of the decoded map the same way. The JSON Schema accepts names in Punycode only, so the editor marks names in Unicode.
