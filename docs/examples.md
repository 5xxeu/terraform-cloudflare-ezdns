# Examples

Part of the documentation of [ezdns](../README.md).

Complete module calls for common setups, each with the records it creates. Each one is planned in CI against a mocked provider, and the tables are generated from the module (`scripts/test-docs-examples.py`), so both stay valid for the current version. Values in angle brackets in the text, and the IDs, tokens and keys in the examples, are placeholders: take the real ones from the service you set up.

- [Mail: Google Workspace](#mail-google-workspace)
- [Mail: Microsoft 365](#mail-microsoft-365)
- [Website: GitHub Pages](#website-github-pages)
- [Website: Netlify or Vercel](#website-netlify-or-vercel)
- [CAA: Only Let's Encrypt](#caa-only-lets-encrypt)
- [Services: SRV Records](#services-srv-records)
- [HTTPS Records](#https-records)
- [Several Teams in One Zone](#several-teams-in-one-zone)
- [Moving a Server Without a Gap](#moving-a-server-without-a-gap)
- [Next to external-dns and cert-manager](#next-to-external-dns-and-cert-manager)

## Mail: Google Workspace

The MX record, SPF, the DKIM key from the Admin console (Apps, Google Workspace, Gmail, Authenticate email) and a DMARC policy. Google accepts a single MX record, `smtp.google.com` with priority 1; zones set up before 2023 may still have the older `aspmx` records, which keep working.

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.16.2"

  zone_id   = var.zone_id
  zone_name = "example.com"

  records = {
    "@" = {
      MX  = [{ content = "smtp.google.com", priority = 1 }]
      TXT = [{ key = "spf", content = "v=spf1 include:_spf.google.com ~all" }]

      # A key keeps each record in place when its value changes (a new DKIM key, a
      # stricter DMARC policy), see "Record Keys" in the README
      "google._domainkey.TXT" = [{ key = "dkim", content = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA" }]
      "_dmarc.TXT"            = [{ key = "dmarc", content = "v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@example.com" }]
    }
  }
}
```

The module creates these records:

<!-- BEGIN_RECORDS -->

| Name | Type | Value | TTL | Record key |
|:-----|:-----|:------|----:|:-----------|
| `example.com` | MX | `smtp.google.com` (priority 1) | 3600 | `@ MX smtp.google.com` |
| `example.com` | TXT | `v=spf1 include:_spf.google.com ~all` | 3600 | `@ TXT spf` |
| `_dmarc.example.com` | TXT | `v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@example.com` | 3600 | `_dmarc TXT dmarc` |
| `google._domainkey.example.com` | TXT | `v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA` | 3600 | `google._domainkey TXT dkim` |

<!-- END_RECORDS -->

- A zone has one SPF record: when another service sends mail for the domain too, add its `include:` to the same record instead of a second one.
- Start DMARC with `p=none` to collect reports, then move to `quarantine` or `reject`. With `key = "dmarc"`, the change is an update in place.

## Mail: Microsoft 365

The values of the MX, autodiscover and DKIM records depend on the domain and the tenant: copy them from the Microsoft 365 admin center (Settings, Domains, DNS records). The SPF value and the Teams federation record are the same for every tenant.

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.16.2"

  zone_id   = var.zone_id
  zone_name = "example.com"

  records = {
    "@" = {
      MX  = [{ content = "example-com.mail.protection.outlook.com", priority = 0 }]
      TXT = [{ key = "spf", content = "v=spf1 include:spf.protection.outlook.com -all" }]

      "_dmarc.TXT" = [{ key = "dmarc", content = "v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@example.com" }]

      # Microsoft rotates the DKIM keys behind these names itself
      "selector1._domainkey.CNAME" = [{ content = "selector1-example-com._domainkey.contoso.onmicrosoft.com" }]
      "selector2._domainkey.CNAME" = [{ content = "selector2-example-com._domainkey.contoso.onmicrosoft.com" }]
    }

    # Outlook finds the mail settings through autodiscover; Cloudflare must not proxy it
    "autodiscover" = {
      CNAME = [{ content = "autodiscover.outlook.com", proxied = false }]
    }

    # Teams federation with other organizations
    "_sipfederationtls._tcp" = {
      SRV = [{ data = { priority = 100, weight = 1, port = 5061, target = "sipfed.online.lync.com" } }]
    }
  }
}
```

The module creates these records:

<!-- BEGIN_RECORDS -->

| Name | Type | Value | TTL | Record key |
|:-----|:-----|:------|----:|:-----------|
| `example.com` | MX | `example-com.mail.protection.outlook.com` (priority 0) | 3600 | `@ MX example-com.mail.protection.outlook.com` |
| `example.com` | TXT | `v=spf1 include:spf.protection.outlook.com -all` | 3600 | `@ TXT spf` |
| `_dmarc.example.com` | TXT | `v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@example.com` | 3600 | `_dmarc TXT dmarc` |
| `_sipfederationtls._tcp.example.com` | SRV | `100 1 5061 sipfed.online.lync.com` | 3600 | `_sipfederationtls._tcp SRV a2b69c9a8166` |
| `autodiscover.example.com` | CNAME | `autodiscover.outlook.com` | 3600 | `autodiscover CNAME` |
| `selector1._domainkey.example.com` | CNAME | `selector1-example-com._domainkey.contoso.onmicrosoft.com` | 3600 | `selector1._domainkey CNAME` |
| `selector2._domainkey.example.com` | CNAME | `selector2-example-com._domainkey.contoso.onmicrosoft.com` | 3600 | `selector2._domainkey CNAME` |

<!-- END_RECORDS -->

The records of Intune (`enterpriseregistration`, `enterpriseenrollment`) are CNAME records too, written the same way as `autodiscover`.

## Website: GitHub Pages

A site with a custom domain on the apex and `www`. GitHub serves it from four IPv4 and four IPv6 addresses and issues the certificate itself, so the records are not proxied. The TXT record verifies the domain for the user or organization (Settings, Pages, Verified domains).

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.16.2"

  zone_id   = var.zone_id
  zone_name = "example.com"

  records = {
    "@" = {
      A = [
        { content = "185.199.108.153", proxied = false },
        { content = "185.199.109.153", proxied = false },
        { content = "185.199.110.153", proxied = false },
        { content = "185.199.111.153", proxied = false },
      ]
      AAAA = [
        { content = "2606:50c0:8000::153", proxied = false },
        { content = "2606:50c0:8001::153", proxied = false },
        { content = "2606:50c0:8002::153", proxied = false },
        { content = "2606:50c0:8003::153", proxied = false },
      ]
      "_github-pages-challenge-example-user.TXT" = [{ content = "0123456789abcdef0123456789abcd" }]
    }

    # www points to the default domain of the user or organization, without the
    # repository name
    "www" = {
      CNAME = [{ content = "example-user.github.io", proxied = false }]
    }
  }
}
```

The module creates these records:

<!-- BEGIN_RECORDS -->

| Name | Type | Value | TTL | Record key |
|:-----|:-----|:------|----:|:-----------|
| `example.com` | A | `185.199.108.153` | 3600 | `@ A 185.199.108.153` |
| `example.com` | A | `185.199.109.153` | 3600 | `@ A 185.199.109.153` |
| `example.com` | A | `185.199.110.153` | 3600 | `@ A 185.199.110.153` |
| `example.com` | A | `185.199.111.153` | 3600 | `@ A 185.199.111.153` |
| `example.com` | AAAA | `2606:50c0:8000::153` | 3600 | `@ AAAA 2606:50c0:8000::153` |
| `example.com` | AAAA | `2606:50c0:8001::153` | 3600 | `@ AAAA 2606:50c0:8001::153` |
| `example.com` | AAAA | `2606:50c0:8002::153` | 3600 | `@ AAAA 2606:50c0:8002::153` |
| `example.com` | AAAA | `2606:50c0:8003::153` | 3600 | `@ AAAA 2606:50c0:8003::153` |
| `_github-pages-challenge-example-user.example.com` | TXT | `0123456789abcdef0123456789abcd` | 3600 | `_github-pages-challenge-example-user TXT d57fb43f336b` |
| `www.example.com` | CNAME | `example-user.github.io` | 3600 | `www CNAME` |

<!-- END_RECORDS -->

With `default_proxied = false` in the module call, the `proxied = false` of each record can go.

## Website: Netlify or Vercel

Netlify recommends a flattened CNAME on the apex, which Cloudflare supports, to its load balancer `apex-loadbalancer.netlify.com` (or an `A` record with `75.2.60.5`), and a CNAME on `www` to the Netlify subdomain of the site. Vercel shows the values for a project in its Settings, Domains; the records have the same shape.

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.16.2"

  zone_id         = var.zone_id
  zone_name       = "example.com"
  default_proxied = false

  records = {
    # A CNAME on the apex is flattened by Cloudflare: it answers with the addresses
    # of the target
    "@" = {
      CNAME = [{ content = "apex-loadbalancer.netlify.com" }]
    }
    "www" = {
      CNAME = [{ content = "brave-curie-12345.netlify.app" }]
    }
  }
}
```

The module creates these records:

<!-- BEGIN_RECORDS -->

| Name | Type | Value | TTL | Record key |
|:-----|:-----|:------|----:|:-----------|
| `example.com` | CNAME | `apex-loadbalancer.netlify.com` | 3600 | `@ CNAME` |
| `www.example.com` | CNAME | `brave-curie-12345.netlify.app` | 3600 | `www CNAME` |

<!-- END_RECORDS -->

A CNAME cannot share its name with other records (the module checks it), except on the apex: MX and TXT records of the apex stay possible next to the flattened CNAME.

## CAA: Only Let's Encrypt

Only Let's Encrypt may issue certificates for the zone, none for wildcard names, and violations are reported by mail. With Universal SSL, Cloudflare adds the CAA records of the certificate authorities it uses for its own certificates itself when a zone has CAA records (they do not show in the dashboard, `dig` shows them), so proxied names keep working.

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.16.2"

  zone_id   = var.zone_id
  zone_name = "example.com"

  records = {
    "@" = {
      CAA = [
        { tag = "issue", content = "letsencrypt.org" },
        { tag = "issuewild", content = ";" },
        { tag = "iodef", content = "mailto:security@example.com" },
      ]
    }
  }
}
```

The module creates these records:

<!-- BEGIN_RECORDS -->

| Name | Type | Value | TTL | Record key |
|:-----|:-----|:------|----:|:-----------|
| `example.com` | CAA | `iodef mailto:security@example.com` | 3600 | `@ CAA iodef mailto:security@example.com` |
| `example.com` | CAA | `issue letsencrypt.org` | 3600 | `@ CAA issue letsencrypt.org` |
| `example.com` | CAA | `issuewild ;` | 3600 | `@ CAA issuewild ;` |

<!-- END_RECORDS -->

CAA records apply to the name and all names below it that have none of their own, so the apex records cover the whole zone.

## Services: SRV Records

Clients find some services through SRV records: here XMPP for clients and servers. Structured records take `data` instead of `content`.

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.16.2"

  zone_id   = var.zone_id
  zone_name = "example.com"

  records = {
    "_xmpp-client._tcp" = {
      SRV = [{ data = { priority = 5, weight = 0, port = 5222, target = "xmpp.example.com" } }]
    }
    "_xmpp-server._tcp" = {
      SRV = [{ data = { priority = 5, weight = 0, port = 5269, target = "xmpp.example.com" } }]
    }
    "xmpp" = {
      A = [{ content = "192.0.2.20", proxied = false }]
    }
  }
}
```

The module creates these records:

<!-- BEGIN_RECORDS -->

| Name | Type | Value | TTL | Record key |
|:-----|:-----|:------|----:|:-----------|
| `_xmpp-client._tcp.example.com` | SRV | `5 0 5222 xmpp.example.com` | 3600 | `_xmpp-client._tcp SRV 684e805d2526` |
| `_xmpp-server._tcp.example.com` | SRV | `5 0 5269 xmpp.example.com` | 3600 | `_xmpp-server._tcp SRV 178141a91006` |
| `xmpp.example.com` | A | `192.0.2.20` | 3600 | `xmpp A 192.0.2.20` |

<!-- END_RECORDS -->

The target of an SRV record must have an address record of its own (not a CNAME), and SRV targets are not proxied: Cloudflare proxies only HTTP and HTTPS.

## HTTPS Records

An HTTPS record tells browsers before the first connection that a name supports HTTP/3 and gives its addresses. The service parameters can be written as fields of `data`, which the module checks and writes in the order of their keys.

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.16.2"

  zone_id   = var.zone_id
  zone_name = "example.com"

  records = {
    "app" = {
      A    = [{ content = "192.0.2.30", proxied = false }]
      AAAA = [{ content = "2001:db8::30", proxied = false }]
      HTTPS = [{
        data = { priority = 1, target = ".", alpn = "h3,h2", ipv4hint = "192.0.2.30", ipv6hint = "2001:db8::30" }
      }]
    }
  }
}
```

The module creates these records:

<!-- BEGIN_RECORDS -->

| Name | Type | Value | TTL | Record key |
|:-----|:-----|:------|----:|:-----------|
| `app.example.com` | A | `192.0.2.30` | 3600 | `app A 192.0.2.30` |
| `app.example.com` | AAAA | `2001:db8::30` | 3600 | `app AAAA 2001:db8::30` |
| `app.example.com` | HTTPS | `1 . alpn="h3,h2" ipv4hint="192.0.2.30" ipv6hint="2001:db8::30"` | 3600 | `app HTTPS c2403c3d36f3` |

<!-- END_RECORDS -->

`target = "."` means the name itself. Cloudflare serves such records only when all records of the name are not proxied; for proxied names with HTTP/2 or HTTP/3 and Universal SSL it generates HTTPS records itself, and ignores ones added by hand.

## Several Teams in One Zone

Each team keeps its records in a file of its own and owns a part of the zone. With one module call, [`record_groups`](../README.md#records-in-several-files) joins the files; with a module call per team (each in its own state, applied by its own pipeline), `owned_names` keeps every call in its part, so a record of one team cannot land in the part of another.

```yaml
# platform.ezdns.yaml
records:
  "@":
    A:
      - content: "192.0.2.10"
    ALIASES:
      - content: "www"
  "api":
    A:
      - content: "192.0.2.11"
```

```yaml
# marketing.ezdns.yaml
records:
  "promo":
    CNAME:
      - { content: "promo.landing.example.net", proxied: false }
  "_acme-challenge.promo":
    TXT:
      - content: "verification-token"
```

```hcl
module "dns_platform" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.16.2"

  zone_id         = var.zone_id
  zone_name       = "example.com"
  default_proxied = true
  default_tags    = ["team:platform"]

  owned_names = { include = ["@"], exclude = ["promo"] }
  records     = yamldecode(file("${path.module}/platform.ezdns.yaml")).records
}

module "dns_marketing" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.16.2"

  zone_id      = var.zone_id
  zone_name    = "example.com"
  default_tags = ["team:marketing"]

  owned_names = { include = ["promo"] }
  records     = yamldecode(file("${path.module}/marketing.ezdns.yaml")).records
}
```

The module creates these records:

<!-- BEGIN_RECORDS -->

| Name | Type | Value | TTL | Record key |
|:-----|:-----|:------|----:|:-----------|
| `example.com` | A | `192.0.2.10` | 1 (auto) | `@ A 192.0.2.10` |
| `api.example.com` | A | `192.0.2.11` | 1 (auto) | `api A 192.0.2.11` |
| `www.example.com` | CNAME | `example.com` | 1 (auto) | `www CNAME` |
| `_acme-challenge.promo.example.com` | TXT | `verification-token` | 3600 | `_acme-challenge.promo TXT 2275f8d2b37d` |
| `promo.example.com` | CNAME | `promo.landing.example.net` | 3600 | `promo CNAME` |

<!-- END_RECORDS -->

- `include = ["@"]` is the whole zone, `exclude` takes names out of it with all names below them; a record outside the owned part fails at `plan` with its name.
- With [`report_unmanaged`](unmanaged-records.md#records-not-in-the-configuration), each call reports the records of its own part only, so the records of the other team are not unmanaged for it.

## Moving a Server Without a Gap

A record whose value changes keeps its place in the state when it has a `key`. To move `app` to a new address with both answering for a while (the steps are in [Changing Values Without a Gap](../README.md#changing-values-without-a-gap)), the old and the new address get their own keys:

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.16.2"

  zone_id   = var.zone_id
  zone_name = "example.com"

  records = {
    "app" = {
      A = [
        { key = "old", content = "192.0.2.10", ttl = 300, proxied = false },
        { key = "new", content = "198.51.100.10", ttl = 300, proxied = false },
      ]
    }
  }
}
```

The module creates these records:

<!-- BEGIN_RECORDS -->

| Name | Type | Value | TTL | Record key |
|:-----|:-----|:------|----:|:-----------|
| `app.example.com` | A | `198.51.100.10` | 300 | `app A new` |
| `app.example.com` | A | `192.0.2.10` | 300 | `app A old` |

<!-- END_RECORDS -->

When the new server works, remove the `old` record; the `new` one stays where it is. Without the overlap, a single record with `key = "web"` changes its value in place.

## Next to external-dns and cert-manager

In a zone where [external-dns](https://github.com/kubernetes-sigs/external-dns) manages the records of a Kubernetes cluster under `k8s` and [cert-manager](https://cert-manager.io) answers ACME DNS challenges, the module manages the rest, reports records nobody manages, and leaves the records of both tools alone:

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.16.2"

  zone_id   = var.zone_id
  zone_name = "example.com"

  # external-dns runs with --domain-filter=k8s.example.com --txt-prefix=extdns-
  owned_names = { include = ["@"], exclude = ["k8s"] }

  report_unmanaged = true
  unmanaged_ignore = [
    { name_regex = "^extdns-", types = ["TXT"] },          # ownership records of external-dns
    { name_regex = "^_acme-challenge\\.", types = ["TXT"] }, # challenges of cert-manager
  ]

  records = {
    "@" = {
      A       = [{ content = "192.0.2.10", proxied = true }]
      ALIASES = [{ content = "www", proxied = true }]
    }
  }
}
```

The module creates these records:

<!-- BEGIN_RECORDS -->

| Name | Type | Value | TTL | Record key |
|:-----|:-----|:------|----:|:-----------|
| `example.com` | A | `192.0.2.10` | 1 (auto) | `@ A 192.0.2.10` |
| `www.example.com` | CNAME | `example.com` | 1 (auto) | `www CNAME` |

<!-- END_RECORDS -->

cert-manager creates each challenge record and deletes it afterwards, so its records stay out of `records`; [`ignore_changes`](../README.md#values-changed-outside-terraform) is for a record that the module creates and another tool only updates. Records of the zone that neither the module nor the two tools manage appear as a warning in the plan and in the sensitive `unmanaged_records` output; with `unmanaged_policy = "error"` they stop the plan. See [Next to external-dns](recipes.md#next-to-external-dns) for why the names must not overlap.
