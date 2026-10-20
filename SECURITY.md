# Security Policy

## Supported Versions

Fixes go into the latest release. Older versions do not get backports: upgrade to the latest 2.x release, see [Upgrading and Migration](docs/upgrading.md).

| Version | Supported |
|---------|-----------|
| Latest 2.x release | Yes |
| Older 2.x releases, 1.x | No |

## Reporting a Vulnerability

Do not open a public issue. Report it privately through [GitHub private vulnerability reporting](https://github.com/5xxeu/terraform-cloudflare-ezdns/security/advisories/new) with:

- the affected version and wrapper (root module, `modules/dns/v4`, `modules/dns/v5`);
- the configuration that shows the problem (without real tokens or zone IDs);
- what happens and what you expected.

You get an answer within 7 days. When the report is confirmed, the fix is released with a GitHub security advisory that credits you, unless you ask not to be named.

## Scope

In scope:

- The module code: for example, records created in another zone or under another name than configured, records deleted or replaced that the configuration does not change, or validation that lets through a value it is meant to reject.
- The release archives and their build provenance.
- The GitHub Actions workflows of this repository.

Out of scope: bugs of the Cloudflare provider, the Cloudflare API and Terraform itself. Report them to their projects.

## Verifying Releases

Each release archive has a checksum in `SHA256SUMS` and signed build provenance, see [Local Copy](docs/sources.md#local-copy). From 2.10.4, the release workflow builds the archives and the GitHub release only after CI passed for the tagged commit, and from 2.16.0 only after the end-to-end test passed for it too and the archives were checked (`scripts/check-archives.sh`: the files of the module, no tests, both archives validate). The tag itself, used by Git sources, exists as soon as it is pushed:

```sh
gh attestation verify terraform-cloudflare-ezdns-<version>.tar.gz \
  --repo 5xxeu/terraform-cloudflare-ezdns \
  --signer-workflow 5xxeu/terraform-cloudflare-ezdns/.github/workflows/release.yml
```

Releases up to 2.12.0 were built in the previous repository, [i386dev/terraform-cloudflare-easy-dns](https://github.com/i386dev/terraform-cloudflare-easy-dns/releases): their archives are named `terraform-cloudflare-easy-dns-<version>.tar.gz` and are verified with `--repo i386dev/terraform-cloudflare-easy-dns --signer-workflow i386dev/terraform-cloudflare-easy-dns/.github/workflows/release.yml`.
