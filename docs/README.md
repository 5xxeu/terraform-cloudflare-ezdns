# Documentation

The [README](../README.md) of the module covers how it works, a quick start, the requirements and when not to use it. These guides cover the rest:

| Guide | What it covers |
|:------|:---------------|
| [Record Model](record-model.md) | Record types and their fields, nested names and aliases, record keys and when to set a `key`, changing values without a gap, values changed outside Terraform |
| [Validation](validation.md) | What fails at `plan`, and what is left to the Cloudflare API |
| [Inputs and Outputs](reference.md) | The inputs, the fields of a record, defaults, comments and tags, the outputs |
| [Records in YAML](yaml.md) | Records in a YAML file with editor support, and records in several files (`record_groups`) |
| [Examples](examples.md) | A full example, and module calls for common setups: mail (Google Workspace, Microsoft 365), websites (GitHub Pages, Netlify, Vercel), CAA, SRV, HTTPS records, several teams in one zone, moving a server, next to external-dns and cert-manager |
| [Troubleshooting](troubleshooting.md) | The common errors and warnings, why they happen and what to do |
| [Importing Existing Records](importing.md) | Adopting the records of an existing zone, and writing its configuration with `tools/zone-to-ezdns.py` |
| [Records Not in the Configuration](unmanaged-records.md) | Reporting records the configuration does not describe, and the part of the zone a module call owns |
| [Checking Plans Before Apply](plan-guard.md) | `tools/plan-guard.py` in CI: deletions, replacements, proxy changes and required records |
| [Recipes](recipes.md) | Record types and fields the module does not support, records next to external-dns, Cloudflare Tunnel, a table of the zone for a wiki, internationalized names |
| [Module Sources](sources.md) | A copy of the module from a release archive, and a Git source |
| [Testing](testing.md) | How the module is tested, and how to test your own records without credentials |
| [Upgrading and Migration](upgrading.md) | Notes for each release that can fail a plan that passed before, from v1 to v2, from provider v4 to v5 |

The examples in these pages are planned in CI (`scripts/test-docs-examples.py`), and their links are checked (`scripts/check-links.py`).
