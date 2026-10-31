# Module Sources

Part of the documentation of [ezdns](../README.md).

Use the module from the Terraform Registry, keep a copy of it in your configuration, or use it from Git. All three give the same module and the same addresses in the state, so a configuration can switch between them without changes in the plan.

The Terraform Registry source is described in the [README](../README.md#terraform-registry).

## Local Copy

A copy in your repository needs neither GitHub nor the Terraform Registry to get the module, and every change of the module shows up in your own history. Each [release](https://github.com/5xxeu/terraform-cloudflare-ezdns/releases) (up to 2.12.0, in the [previous repository](https://github.com/i386dev/terraform-cloudflare-easy-dns/releases), with archives named `terraform-cloudflare-easy-dns-*`) has an archive of the module with a checksum:

```sh
REPO=https://github.com/5xxeu/terraform-cloudflare-ezdns
VERSION=v2.21.0
ARCHIVE="terraform-cloudflare-ezdns-${VERSION}.tar.gz"
curl -fsSL -O "${REPO}/releases/download/${VERSION}/${ARCHIVE}"
curl -fsSL -O "${REPO}/releases/download/${VERSION}/SHA256SUMS"
sha256sum --check --ignore-missing SHA256SUMS   # macOS: shasum -a 256 --check
# Optional: the archive was built by the release workflow of this repository (releases up to 2.12.0: see SECURITY.md)
gh attestation verify "${ARCHIVE}" --repo 5xxeu/terraform-cloudflare-ezdns \
  --signer-workflow 5xxeu/terraform-cloudflare-ezdns/.github/workflows/release.yml
mkdir -p modules/ezdns
tar -xzf "${ARCHIVE}" -C modules/ezdns
```

Commit `modules/ezdns` together with your configuration and use it as a local module:

| Cloudflare provider | `source` |
|:--------------------|:---------|
| v5 | `./modules/ezdns` |
| v4 | `./modules/ezdns/modules/dns/v4` |

Keep the directory together: the wrappers use the shared core module through a relative path. The Cloudflare provider is still installed from the Terraform Registry on `terraform init`; for fully offline use, set up a provider mirror with `terraform providers mirror`. `modules/ezdns/VERSION` shows the version of the copy; to upgrade, replace the directory with the archive of the new version and follow [Upgrading and Migration](upgrading.md#upgrading-and-migration).

### In a Larger Repository

Each release also has a provider v5 archive, `terraform-cloudflare-ezdns-v5-<version>.tar.gz` (in the same `SHA256SUMS`): the root module, `modules/dns/v5` and `modules/dns/records`, without the v4 wrapper and without `migrate-from-v4.tf`, the `moved` block for configurations that used the v4 wrapper. It is meant for repositories that pin provider v5 and run tools over every directory, where the v4 wrapper's `~> 4.41` would conflict. Updating such a copy is a plain replacement of the directory.

What a copy may change without affecting the module:

- `versions.tf` (root and `modules/dns/v5`) may be replaced by the repository's own pin, as long as it allows Terraform `>= 1.8.0` and the Cloudflare provider `>= 5.26` within v5
- `schema/` is only needed for records in YAML, and the `README.md` files of the submodules are generated reference
- With the full archive and no history on provider v4: `modules/dns/v4` and `modules/dns/v5/migrate-from-v4.tf` may be dropped, which gives the v5 archive

## Git Source

To fetch the module on `terraform init` instead, use a Git source with a tag (or the URL of your own mirror):

```hcl
source = "git::https://github.com/5xxeu/terraform-cloudflare-ezdns.git?ref=v2.21.0"
```

For provider v4, add `//modules/dns/v4` before `?ref=`. In CI, where every run starts from a clean checkout, add `&depth=1` after the tag (`?ref=v2.21.0&depth=1`) to fetch only that commit instead of the whole history.
