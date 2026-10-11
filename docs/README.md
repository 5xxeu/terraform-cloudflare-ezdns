# Documentation

The [README](../README.md) of the module covers how it works, the record model, validation, inputs and outputs. These guides go further:

| Guide | What it covers |
|:------|:---------------|
| [Examples](examples.md) | Module calls for common setups: mail (Google Workspace, Microsoft 365), websites (GitHub Pages, Netlify, Vercel), CAA, SRV, HTTPS records, several teams in one zone, moving a server, next to external-dns and cert-manager |
| [Troubleshooting](troubleshooting.md) | The common errors and warnings, why they happen and what to do |
| [Importing Existing Records](importing.md) | Adopting the records of an existing zone, and writing its configuration with `tools/zone-to-ezdns.py` |
| [Records Not in the Configuration](unmanaged-records.md) | Reporting records the configuration does not describe, and the part of the zone a module call owns |
| [Checking Plans Before Apply](plan-guard.md) | `tools/plan-guard.py` in CI: deletions, replacements, proxy changes and required records |
| [Recipes](recipes.md) | Record types and fields the module does not support, records next to external-dns, internationalized names |
| [Testing](testing.md) | How the module is tested, and how to test your own records without credentials |
| [Upgrading and Migration](upgrading.md) | Notes for each release that can fail a plan that passed before, from v1 to v2, from provider v4 to v5 |

The examples in these pages are planned in CI (`scripts/test-docs-examples.py`), and their links are checked (`scripts/check-links.py`).
