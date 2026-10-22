#!/usr/bin/env python3
"""Check current ezdns references against the first release in CHANGELOG.md.

Historical migration examples are intentionally excluded. Provider versions do not
match these patterns. An optional tag checks release-time consistency as well.
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SEMVER = r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?"
PATTERNS = [
    re.compile(r'source\s*=\s*"5xxeu/ezdns/cloudflare[^"\n]*"\s*\n\s*(?:#\s*)?version\s*=\s*"(?P<version>[^"\n]+)"'),
    re.compile(r'(?m)^VERSION=v(?P<version>[^\s]+)'),
    re.compile(r'terraform-cloudflare-ezdns\.git(?:[^\s"`]*?)\?ref=v(?P<version>' + SEMVER + r')'),
    re.compile(r'raw\.githubusercontent\.com/5xxeu/terraform-cloudflare-ezdns/v(?P<version>' + SEMVER + r')/'),
    re.compile(r'~> (?P<version>' + SEMVER + r')(?=`)'),
]


def check(root, tag=None):
    heading = re.search(r'^## \[(' + SEMVER + r')\]', (root / 'CHANGELOG.md').read_text(), re.M)
    if not heading:
        return ['CHANGELOG.md: no release version found']
    expected = heading.group(1)
    errors = []
    if tag is not None and tag != 'v' + expected:
        errors.append(f'tag {tag}: expected v{expected} from CHANGELOG.md')
    paths = [root / 'README.md']
    paths += sorted(p for p in (root / 'docs').glob('*.md') if p.name != 'upgrading.md')
    examples = [root / 'examples' / kind / 'main.tf' for kind in ('v5', 'yaml', 'import')]
    for path in paths + examples:
        content = path.read_text()
        found = 0
        for pattern in PATTERNS:
            for match in pattern.finditer(content):
                found += 1
                actual = match.group('version')
                # README recommends a minor pin; its patch must start at zero.
                wanted = '.'.join(expected.split('.')[:2]) + '.0' if match.group(0).startswith('~> ') else expected
                if actual != wanted:
                    line = content.count('\n', 0, match.start('version')) + 1
                    errors.append(f'{path.relative_to(root)}:{line}: {actual}, expected {wanted}')
        if path in examples and not found:
            errors.append(f'{path.relative_to(root)}: missing Registry version comment')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', help='release tag, e.g. v2.18.0')
    args = parser.parse_args()
    errors = check(ROOT, args.tag)
    for error in errors:
        print(error, file=sys.stderr)
    if not errors:
        print('Current ezdns version references are in sync')
    return int(bool(errors))


if __name__ == '__main__':
    sys.exit(main())
