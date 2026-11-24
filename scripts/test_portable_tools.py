import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from build_web_cache import generate
from create_manifest import create_manifest
from package_desktop import package


class PortableToolsTest(unittest.TestCase):
    def test_offline_cache_is_deterministic_and_changes_with_asset_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'index.html').write_text('index')
            (root / 'flutter_bootstrap.js').write_text('bootstrap')
            (root / 'a b.txt').write_text('first')
            first = generate(root)
            self.assertEqual(first, generate(root))
            worker = (root / 'amid-sw.js').read_text()
            self.assertIn('a%20b.txt', worker)
            self.assertIn('self.registration.scope', worker)
            (root / 'a b.txt').write_text('second')
            self.assertNotEqual(first['version'], generate(root)['version'])

    def test_package_contains_complete_bundle_and_rejects_outside_links(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundle = root / 'bundle'
            (bundle / 'data').mkdir(parents=True)
            executable = bundle / 'amid_offgrid'
            executable.write_bytes(b'executable'); executable.chmod(0o755)
            (bundle / 'data' / 'asset').write_bytes(b'asset')
            archive = root / 'app.zip'
            self.assertEqual(package(bundle, archive), 2)
            with zipfile.ZipFile(archive) as z:
                self.assertEqual(z.read('data/asset'), b'asset')
                self.assertTrue((z.getinfo('amid_offgrid').external_attr >> 16) & 0o111)
            outside = root / 'outside'; outside.write_text('private')
            (bundle / 'link').symlink_to(outside)
            with self.assertRaises(ValueError): package(bundle, archive)

    def test_portable_manifests_keep_devices_and_stores_unverified(self):
        with tempfile.TemporaryDirectory() as directory:
            for platform, extension, signing in [
                ('windows', '.zip', 'unsigned'), ('linux', '.zip', 'unsigned'),
                ('macos', '.zip', 'unsigned'), ('web', '.zip', 'unsigned'),
                ('wearos', '.apk', 'development'), ('watchos', '.zip', 'unsigned'),
            ]:
                with self.subTest(platform=platform):
                    path = Path(directory) / (platform + extension)
                    path.write_bytes(b'package')
                    record = create_manifest([path], commit='a'*40,
                        platform=platform, signing=signing,
                        run_url='https://github.com/owner/repo/actions/runs/1')
                    self.assertEqual(record['deviceTesting'], 'not_run')
                    self.assertFalse(record['artifacts'][0]['physicalDeviceTested'])


if __name__ == '__main__': unittest.main()
