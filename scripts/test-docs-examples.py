#!/usr/bin/env python3
"""Plans every module call of the README and docs against a mocked provider, and
checks the tables of the records they create.

Each ```hcl block with a whole module call of 5xxeu/ezdns/cloudflare (not a fragment
with "# ...") is one example; the ```yaml blocks of the same section whose first line
is "# <file>.yaml" are its files. The example goes into a directory of its own, with
the source pointing to this repository, and passes when terraform test plans it
without errors and warnings.

An example followed by <!-- BEGIN_RECORDS --> and <!-- END_RECORDS --> (before the
next code block or section) gets the table of its records between them: the module
calls run through modules/dns/compile, which gives the records without a provider.
The tables must match; --write updates them.

    python3 scripts/test-docs-examples.py [--write] [README.md docs/*.md ...]

Exit status: 0 when every example passes and every table matches, 1 otherwise.
"""

import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = re.compile(r'^(\s*)source\s*=\s*"5xxeu/ezdns/cloudflare"\s*$', re.M)
VERSION = re.compile(r'^\s*version\s*=\s*"[^"]*"\s*\n', re.M)
BEGIN, END = "<!-- BEGIN_RECORDS -->", "<!-- END_RECORDS -->"
TEST = """mock_provider "cloudflare" {}

variables {
  zone_id = "023e105f4ecef8ad9ca31a8372d0c353"
}

run "plan" {
  command = plan
}
"""
PROVIDERS = 'terraform {\n  required_providers {\n    cloudflare = { source = "cloudflare/cloudflare" }\n  }\n}\n'


def examples(text, name):
    """Yields a dict per module call of the text: section, hcl, files ({name: yaml})
    and table (the span of the text between the markers after the block, or None)."""
    section, files = name, {}
    # Code blocks also in list items, indented
    pattern = re.compile(r"^## ([^\n]+)$|^( *)```(\w+)\n(.*?)^\2```$", re.M | re.S)
    matches = list(pattern.finditer(text))
    for i, m in enumerate(matches):
        if m.group(1):
            section, files = m.group(1), {}
            continue
        lang, indent = m.group(3), len(m.group(2))
        body = "".join(line[indent:] for line in m.group(4).splitlines(keepends=True))
        if lang == "yaml":
            first = body.split("\n", 1)[0]
            file = re.fullmatch(r"#\s*(\S+\.ya?ml)", first)
            if file:
                files[file.group(1)] = body
        # A block with "# ..." is a fragment, not a whole module call
        elif lang == "hcl" and SOURCE.search(body) and not re.search(r"^\s*# \.\.\.", body, re.M):
            limit = matches[i + 1].start() if i + 1 < len(matches) else len(text)
            begin = text.find(BEGIN, m.end(), limit)
            end = text.find(END, begin, limit) if begin >= 0 else -1
            table = (begin + len(BEGIN), end) if begin >= 0 and end >= 0 else None
            yield {"section": section, "hcl": body, "files": dict(files), "table": table}


def terraform(args, d, env):
    r = subprocess.run(["terraform", *args, "-no-color"], cwd=d, capture_output=True, text=True, env=env)
    return r.returncode, r.stdout + r.stderr


def local_source(path, d):
    # A local source starts with ./ or ../
    return os.path.relpath(path, d) + "/"


def plan_example(ex, d, env):
    """Plans the example against the mocked provider; returns an error text or None."""
    main = VERSION.sub("", SOURCE.sub(lambda m: f'{m.group(1)}source = "{local_source(ROOT, d)}"', ex["hcl"]))
    # The mocked provider is cloudflare/cloudflare: add it to the providers of the example
    if "required_providers {" in main and "cloudflare = " not in main:
        main = main.replace("required_providers {", 'required_providers {\n    cloudflare = { source = "cloudflare/cloudflare" }', 1)
    zone_id = "" if 'variable "zone_id"' in main else '\nvariable "zone_id" {\n  type = string\n}\n'
    (d / "main.tf").write_text(main + zone_id)
    if "required_providers" not in main:
        (d / "versions.tf").write_text(PROVIDERS)
    for name, text in ex["files"].items():
        (d / name).write_text(text)
    (d / "tests").mkdir()
    (d / "tests" / "plan.tftest.hcl").write_text(TEST)
    code, out = terraform(["init", "-backend=false"], d, env)
    if code != 0:
        return out
    code, out = terraform(["test"], d, env)
    if code != 0 or "Warning" in out:
        return out
    return None


def compile_inputs():
    text = (ROOT / "modules" / "dns" / "compile" / "variables.tf").read_text()
    return set(re.findall(r'^variable "(\w+)"', text, re.M))


def depth(line):
    """The change of the bracket depth of a line, outside of strings and comments."""
    d, quoted, escaped = 0, False, False
    for i, c in enumerate(line):
        if quoted:
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                quoted = False
        elif c == '"':
            quoted = True
        elif c == "#" or line.startswith("//", i):
            break
        elif c in "([{":
            d += 1
        elif c in ")]}":
            d -= 1
    return d


def to_compile(hcl, inputs, source):
    """The module calls of the example with the compile submodule as source and only the
    arguments it takes; other blocks stay as they are. Returns (hcl, module names)."""
    out, names = [], []
    lines = hcl.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r'^module "(\w+)" \{$', line)
        if not m:
            out.append(line)
            i += 1
            continue
        names.append(m.group(1))
        out.append(line)
        out.append(f'  source = "{source}"')
        i += 1
        while i < len(lines) and lines[i] != "}":
            attr = re.match(r"^  (\w+)\s*=", lines[i])
            start, level = i, depth(lines[i])
            i += 1
            while level > 0 and i < len(lines):
                level += depth(lines[i])
                i += 1
            if attr and attr.group(1) in inputs:
                out.extend(lines[start:i])
        out.append("}")
        i += 1
    return "\n".join(out), names


def records(ex, d, env):
    """The records of the module calls of the example, as compile gives them."""
    main, names = to_compile(ex["hcl"], compile_inputs(), local_source(ROOT / "modules" / "dns" / "compile", d))
    outputs = "".join(f'\noutput "records_{n}" {{\n  value = module.{n}.records\n}}\n' for n in names)
    (d / "main.tf").write_text(main + "\n" + outputs)
    for name, text in ex["files"].items():
        (d / name).write_text(text)
    for args in (["init", "-backend=false"], ["plan", "-out=tfplan"]):
        code, out = terraform(args, d, env)
        if code != 0:
            raise RuntimeError(out)
    show = subprocess.run(["terraform", "show", "-json", "tfplan"], cwd=d, capture_output=True, text=True, env=env, check=True)
    values = json.loads(show.stdout)["planned_values"]["outputs"]
    result = []
    for n in names:
        result += list(values[f"records_{n}"]["value"].items())
    return result


def value(r):
    data = r.get("data") or {}
    t = r["type"]
    if t == "CAA":
        flags = "" if str(data.get("flags")) == "0" else f"{data.get('flags')} "
        return f"{flags}{data.get('tag')} {data.get('value')}"
    if t == "SRV":
        return f"{data.get('priority')} {data.get('weight')} {data.get('port')} {data.get('target')}"
    if t in ("HTTPS", "SVCB"):
        return " ".join(str(v) for v in (data.get("priority"), data.get("target"), data.get("value")) if v is not None)
    if data:
        return " ".join(f"{k}={v}" for k, v in sorted(data.items()))
    return r.get("content") or ""


def table(rows):
    def cell(text):
        return text.replace("|", "\\|")
    lines = ["| Name | Type | Value | TTL | Record key |", "|:-----|:-----|:------|----:|:-----------|"]
    for key, r in rows:
        v = f"`{cell(value(r))}`"
        if r.get("priority") is not None and r["type"] in ("MX", "URI"):
            v += f" (priority {r['priority']})"
        ttl = "1 (auto)" if r["ttl"] == 1 else str(r["ttl"])
        lines.append(f"| `{r['fqdn']}` | {r['type']} | {v} | {ttl} | `{cell(key)}` |")
    return "\n".join(lines)


def main(argv):
    write = "--write" in argv
    paths = [pathlib.Path(p) for p in argv if p != "--write"] or [ROOT / "README.md", *sorted((ROOT / "docs").glob("*.md"))]
    failed = 0
    count = 0
    # The provider is downloaded once for all examples
    cache = tempfile.TemporaryDirectory(prefix="docs-example-plugins-")
    env = dict(os.environ, TF_PLUGIN_CACHE_DIR=os.environ.get("TF_PLUGIN_CACHE_DIR", cache.name))
    for path in paths:
        text = path.read_text()
        replacements = []
        for ex in examples(text, path.stem):
            count += 1
            # Inside the repository, so that the relative source stays short and the
            # module is found the same way on every machine
            with tempfile.TemporaryDirectory(dir=ROOT, prefix=".docs-example-") as workdir:
                error = plan_example(ex, pathlib.Path(workdir), env)
            if not error and ex["table"]:
                with tempfile.TemporaryDirectory(dir=ROOT, prefix=".docs-example-") as workdir:
                    try:
                        generated = "\n\n" + table(records(ex, pathlib.Path(workdir), env)) + "\n\n"
                    except RuntimeError as e:
                        error = f"records: {e}"
                if not error:
                    start, end = ex["table"]
                    if text[start:end] != generated:
                        if write:
                            replacements.append((start, end, generated))
                        else:
                            error = "the table of records differs from the records of the example (run with --write)"
            if error:
                failed += 1
                print(f"FAIL {path.name}: {ex['section']}\n{error}", file=sys.stderr)
            else:
                print(f"ok   {path.name}: {ex['section']}")
        for start, end, generated in sorted(replacements, reverse=True):
            text = text[:start] + generated + text[end:]
        if replacements:
            path.write_text(text)
            print(f"wrote {len(replacements)} tables to {path.name}")
    if count == 0:
        print("no examples found", file=sys.stderr)
        return 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
