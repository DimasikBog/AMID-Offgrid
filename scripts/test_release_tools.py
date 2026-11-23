import hashlib
import json
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

from create_manifest import create_manifest
from package_ios import package_app


class ReleaseToolsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def app(self):
        app = self.root / 'Runner.app'
        app.mkdir()
        (app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleExecutable': 'Runner', 'CFBundleIdentifier': 'com.amid.offgrid',
            'CFBundleShortVersionString': '0.3.0', 'CFBundleVersion': '3',
            'CFBundleSupportedPlatforms': ['iPhoneOS']}))
        binary = app / 'Runner'
        binary.write_bytes(struct.pack('<II', 0xfeedfacf, 0x100000c) + b'test fixture')
        binary.chmod(0o755)
        return app

    def test_ipa_layout_and_executable_permissions(self):
        app = self.app()
        output = self.root / 'app.ipa'
        package_app(app, output)
        with zipfile.ZipFile(output) as archive:
            self.assertIn('Payload/Runner.app/Info.plist', archive.namelist())
            self.assertTrue((archive.getinfo('Payload/Runner.app/Runner').external_attr >> 16) & 0o111)

    def test_escaping_symlink_is_rejected(self):
        app = self.app()
        (self.root / 'outside').write_text('must not be packaged')
        (app / 'link').symlink_to('../outside')
        with self.assertRaises(ValueError):
            package_app(app, self.root / 'app.ipa')

    def test_simulator_and_signed_bundles_are_rejected(self):
        app = self.app()
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        info['CFBundleSupportedPlatforms'] = ['iPhoneSimulator']
        (app / 'Info.plist').write_bytes(plistlib.dumps(info))
        with self.assertRaises(ValueError):
            package_app(app, self.root / 'app.ipa')
        info['CFBundleSupportedPlatforms'] = ['iPhoneOS']
        (app / 'Info.plist').write_bytes(plistlib.dumps(info))
        (app / '_CodeSignature').mkdir()
        with self.assertRaises(ValueError):
            package_app(app, self.root / 'app.ipa')

    def test_manifest_hashes_and_unverified_states(self):
        artifact = self.root / 'app.apk'
        artifact.write_bytes(b'example artifact, not an Android build')
        manifest = create_manifest([artifact], commit='a' * 40, platform='android',
            signing='development', run_url='https://github.com/owner/repo/actions/runs/123')
        self.assertEqual(manifest['artifacts'][0]['sha256'], hashlib.sha256(artifact.read_bytes()).hexdigest())
        self.assertFalse(manifest['artifacts'][0]['physicalDeviceTested'])
        self.assertEqual(manifest['storeSubmission'], 'not_run')
        self.assertEqual(manifest['quality'], 'not_recorded')
        self.assertEqual(json.loads(json.dumps(manifest)), manifest)

    def test_manifest_requires_an_exact_commit(self):
        with self.assertRaises(ValueError):
            create_manifest([], commit='main', platform='ios', signing='unsigned', run_url='')


if __name__ == '__main__':
    unittest.main()
