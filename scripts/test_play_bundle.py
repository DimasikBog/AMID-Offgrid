import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from build_play_bundle import PACK, staged_model
from prepare_offline_payload import ROOT, catalog, split_model
from verify_offline_payload import verify
from verify_play_bundle import verify_delivery


class PlayBundleTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data = copy.deepcopy(catalog())
        self.payload = b'GGUF split-install test data, not a real model'
        self.model = self.data['model']
        self.model.update(bytes=len(self.payload), sha256=hashlib.sha256(self.payload).hexdigest())
        self.folder = self.root / 'assets/offline_model'
        self.folder.mkdir(parents=True)
        self.file = self.root / 'model.gguf'
        self.file.write_bytes(self.payload)
        split_model(self.model, self.file, self.folder, chunk_bytes=8)
        (self.folder / 'catalog.json').write_text(json.dumps(self.data))

    def test_build_failure_restores_every_original_part(self):
        original = {p.name: p.read_bytes() for p in self.folder.glob('*.part')}
        with self.assertRaisesRegex(RuntimeError, 'simulated build failure'):
            with staged_model(self.root, self.model):
                self.assertEqual(list(self.folder.glob('*.part')), [])
                self.assertEqual({p.name: p.read_bytes() for p in (self.root / PACK).iterdir()}, original)
                raise RuntimeError('simulated build failure')
        self.assertEqual({p.name: p.read_bytes() for p in self.folder.glob('*.part')}, original)
        self.assertFalse((self.root / PACK).exists())

    def test_interrupted_or_concurrent_pack_is_not_overwritten(self):
        target = self.root / PACK
        target.mkdir(parents=True)
        (target / 'keep').write_bytes(b'unique bytes')
        with self.assertRaises(FileExistsError):
            with staged_model(self.root, self.model):
                self.fail('must not start a concurrent build')
        self.assertEqual((target / 'keep').read_bytes(), b'unique bytes')

    def aab(self, extra=None, corrupt=False):
        path = self.root / 'app.aab'
        with staged_model(self.root, self.model), zipfile.ZipFile(path, 'w') as archive:
            for file in self.folder.iterdir():
                archive.write(file, 'base/assets/flutter_assets/assets/offline_model/' + file.name)
            for file in (self.root / PACK).iterdir():
                content = file.read_bytes()
                if corrupt and file.name == 'model-001.part': content = b'badbytes'
                archive.writestr('offline_model/assets/flutter_assets/assets/offline_model/' + file.name, content)
            for key in ['map', 'knowledge']:
                archive.write(ROOT / self.data[key]['asset'], 'base/assets/flutter_assets/' + self.data[key]['asset'])
            archive.writestr('offline_model/manifest/AndroidManifest.xml', b'proto manifest placeholder')
            if extra: archive.writestr(extra, b'unexpected data')
        return path

    def test_aab_reads_model_from_pack_and_catalog_from_base(self):
        self.assertEqual(verify(self.aab(), self.data)['sha256'], self.model['sha256'])

    def test_corruption_base_duplication_and_code_in_pack_are_rejected(self):
        with self.assertRaises(ValueError): verify(self.aab(corrupt=True), self.data)
        for extra in ['base/assets/duplicate.gguf', 'offline_model/dex/classes.dex',
                      'offline_model/assets/undeclared.part']:
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                verify(self.aab(extra=extra), self.data)

    def test_only_unconditional_install_time_ai_manifest_is_accepted(self):
        xml = '''<manifest xmlns:dist="http://schemas.android.com/apk/distribution" split="offline_model">
          <dist:module dist:type="ai-pack"><dist:delivery><dist:install-time/></dist:delivery></dist:module>
        </manifest>'''
        verify_delivery(xml)
        for invalid in [xml.replace('install-time', 'on-demand'), xml.replace('ai-pack', 'asset-pack'),
                        xml.replace('<dist:install-time/>', '<dist:install-time><dist:conditions/></dist:install-time>')]:
            with self.assertRaises(ValueError): verify_delivery(invalid)


if __name__ == '__main__':
    unittest.main()
