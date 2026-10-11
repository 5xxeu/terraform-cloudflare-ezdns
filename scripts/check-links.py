#!/usr/bin/env python3
"""Checks the links of the Markdown files of the repository: relative links and links to
this repository on GitHub (blob/main, tree/main, and the README with an anchor) must
point to files that exist and to headings that exist in them. Other links are not
fetched.

    python3 scripts/check-links.py

Exit status: 0 when every link resolves, 1 otherwise.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = "https://github.com/5xxeu/terraform-cloudflare-ezdns"
LINK = re.compile(r"\]\(([^)\s]+)\)")


def anchor(heading):
    """The anchor GitHub gives a heading."""
    a = re.sub(r"[^\w\- ]", "", heading.strip().lower())
    return a.replace(" ", "-")


def without_blocks(text):
    return re.sub(r"^( *)```.*?^\1```$", "", text, flags=re.M | re.S)


def without_code(text):
    return re.sub(r"`[^`\n]*`", "", without_blocks(text))


def anchors(path, cache={}):
    if path not in cache:
        text = without_blocks(path.read_text())
        # Anchors of HTML elements, as terraform-docs writes them
        found = set(re.findall(r'<a (?:name|id)="([^"]+)"', text))
        for m in re.finditer(r"^#{1,6} (.*)$", text, re.M):
            a = anchor(m.group(1).replace("`", ""))
            # Repeated headings get -1, -2, ...
            n, candidate = 0, a
            while candidate in found:
                n += 1
                candidate = f"{a}-{n}"
            found.add(candidate)
        cache[path] = found
    return cache[path]


def target(link, source):
    """The local path and anchor of a link, or None for links outside the repository."""
    if link.startswith(REPO):
        rest = link[len(REPO):]
        m = re.match(r"^/(?:blob|tree)/main/([^#]*)(?:#(.*))?$", rest)
        if m:
            return ROOT / m.group(1), m.group(2)
        m = re.match(r"^/?(?:#(.*))?$", rest)
        if m:
            return ROOT / "README.md", None if m.group(1) == "readme" else m.group(1)
        return None
    if re.match(r"^[a-z][a-z0-9+.-]*:", link):
        return None
    path, _, frag = link.partition("#")
    # Markdown escapes in anchors (terraform-docs writes input\_records)
    return (source.parent / path if path else source), frag.replace("\\", "") or None


def main():
    files = [p for p in ROOT.rglob("*.md") if not any(part.startswith(".") for part in p.relative_to(ROOT).parts)]
    broken = []
    for source in sorted(files):
        for link in LINK.findall(without_code(source.read_text())):
            t = target(link, source)
            if t is None:
                continue
            path, frag = t
            if not path.exists():
                broken.append((source, link, "no such file"))
            elif frag and path.suffix == ".md" and frag not in anchors(path):
                broken.append((source, link, "no such heading"))
    for source, link, why in broken:
        print(f"{source.relative_to(ROOT)}: {link} ({why})", file=sys.stderr)
    print(f"{len(files)} files, {len(broken)} broken links")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
