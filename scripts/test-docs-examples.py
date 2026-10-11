#!/usr/bin/env python3
"""Plans every module call of the README and docs against a mocked provider.

Each ```hcl block with a whole module call of 5xxeu/ezdns/cloudflare (not a fragment
with "# ...") is one example; the
```yaml blocks of the same section whose first line is "# <file>.yaml" are its files.
The example goes into a directory of its own, with the source pointing to this
repository, and passes when terraform test plans it without errors and warnings.

    python3 scripts/test-docs-examples.py [README.md docs/*.md ...]

Exit status: 0 when every example passes, 1 otherwise.
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = re.compile(r'^(\s*)source\s*=\s*"5xxeu/ezdns/cloudflare"\s*$', re.M)
VERSION = re.compile(r'^\s*version\s*=\s*"[^"]*"\s*\n', re.M)
TEST = """mock_provider "cloudflare" {}

variables {
  zone_id = "023e105f4ecef8ad9ca31a8372d0c353"
}

run "plan" {
  command = plan
}
"""


def examples(path):
    """Yields (section, hcl, {file name: yaml}) for each module call of the file."""
    section, files = path.stem, {}
    for m in re.finditer(r"^## ([^\n]+)$|^```(\w+)\n(.*?)^```$", path.read_text(), re.M | re.S):
        if m.group(1):
            section, files = m.group(1), {}
        elif m.group(2) == "yaml":
            first = m.group(3).split("\n", 1)[0]
            name = re.fullmatch(r"#\s*(\S+\.ya?ml)", first)
            if name:
                files[name.group(1)] = m.group(3)
        # A block with "# ..." is a fragment, not a whole module call
        elif m.group(2) == "hcl" and SOURCE.search(m.group(3)) and not re.search(r"^\s*# \.\.\.", m.group(3), re.M):
            yield section, m.group(3), dict(files)


def run(section, hcl, files, workdir, env):
    d = pathlib.Path(workdir)
    # A local source starts with ./ or ../
    source = os.path.relpath(ROOT, d) + "/"
    main = VERSION.sub("", SOURCE.sub(lambda m: f'{m.group(1)}source = "{source}"', hcl))
    # The mocked provider is cloudflare/cloudflare: add it to the providers of the example
    if "required_providers {" in main and "cloudflare = " not in main:
        main = main.replace("required_providers {", 'required_providers {\n    cloudflare = { source = "cloudflare/cloudflare" }', 1)
    (d / "main.tf").write_text(main + '\nvariable "zone_id" {\n  type = string\n}\n')
    if "required_providers" not in main:
        (d / "versions.tf").write_text('terraform {\n  required_providers {\n    cloudflare = { source = "cloudflare/cloudflare" }\n  }\n}\n')
    for name, text in files.items():
        (d / name).write_text(text)
    (d / "tests").mkdir()
    (d / "tests" / "plan.tftest.hcl").write_text(TEST)
    init = subprocess.run(["terraform", "init", "-backend=false", "-no-color"], cwd=d, capture_output=True, text=True, env=env)
    if init.returncode != 0:
        return init.stdout + init.stderr
    test = subprocess.run(["terraform", "test", "-no-color"], cwd=d, capture_output=True, text=True, env=env)
    out = test.stdout + test.stderr
    if test.returncode != 0 or "Warning" in out:
        return out
    return None


def main(argv):
    paths = [pathlib.Path(p) for p in argv] or [ROOT / "README.md", *sorted((ROOT / "docs").glob("*.md"))]
    failed = 0
    count = 0
    # The provider is downloaded once for all examples
    cache = tempfile.TemporaryDirectory(prefix="docs-example-plugins-")
    env = dict(os.environ, TF_PLUGIN_CACHE_DIR=os.environ.get("TF_PLUGIN_CACHE_DIR", cache.name))
    for path in paths:
        for section, hcl, files in examples(path):
            count += 1
            # Inside the repository, so that the relative source stays short and the
            # module is found the same way on every machine
            with tempfile.TemporaryDirectory(dir=ROOT, prefix=".docs-example-") as workdir:
                error = run(section, hcl, files, workdir, env)
            if error:
                failed += 1
                print(f"FAIL {path.name}: {section}\n{error}", file=sys.stderr)
            else:
                print(f"ok   {path.name}: {section}")
    if count == 0:
        print("no examples found", file=sys.stderr)
        return 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
