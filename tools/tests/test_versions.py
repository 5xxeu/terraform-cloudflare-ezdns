"""Version checks cover current examples without confusing provider pins or history."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('check_versions', Path(__file__).resolve().parents[2] / 'scripts/check-versions.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)


class VersionTest(unittest.TestCase):
    def test_current_references(self):
        self.assertEqual(v.check(v.ROOT), [])

    def test_stale_example_comment_and_missing_comment(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'docs').mkdir()
            (root / 'CHANGELOG.md').write_text('## [Unreleased]\n## [2.18.1] - 2026-10-22\n')
            (root / 'README.md').write_text('version = "~> 5.26"\n')
            (root / 'docs/upgrading.md').write_text('VERSION=v1.0.0\n')
            for name in ('v5', 'yaml', 'import'):
                path = root / 'examples' / name
                path.mkdir(parents=True)
                (path / 'main.tf').write_text('# source = "5xxeu/ezdns/cloudflare"\n# version = "2.18.1"\n')
            self.assertEqual(v.check(root, 'v2.18.1'), [])
            stale = root / 'examples/yaml/main.tf'
            stale.write_text(stale.read_text().replace('2.18.1', '2.12.2'))
            self.assertIn('examples/yaml/main.tf:2: 2.12.2, expected 2.18.1', v.check(root))
            stale.write_text('source = "../.."\n')
            self.assertIn('examples/yaml/main.tf: missing Registry version comment', v.check(root))
            self.assertTrue(v.check(root, 'v2.18.0'))
