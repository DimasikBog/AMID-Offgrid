import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from prepare_offline_payload import catalog, download, split_model, verify_parts, ROOT
from verify_offline_payload import verify


class Response(io.BytesIO):
    def __init__(self, data, status=200, headers=None):
        super().__init__(data)
        self.status = status
        self.headers = headers or {}


class OfflinePayloadTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.payload = b'GGUF independently checked synthetic payload'
        self.data = copy.deepcopy(catalog(ROOT))
        self.model = self.data['model']
        self.model.update(bytes=len(self.payload), sha256=hashlib.sha256(self.payload).hexdigest())
        self.folder = self.root / 'app/data/flutter_assets/assets/offline_model'
        self.folder.mkdir(parents=True)
        for name in ['map', 'knowledge']:
            data = (ROOT / self.data[name]['asset']).read_bytes()
            path = self.folder.parent.parent / self.data[name]['asset']
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        (self.folder / 'catalog.json').write_text(json.dumps(self.data))
        self.source = self.root / 'model.gguf'
        self.source.write_bytes(self.payload)

    def test_full_payload_matches_input_and_real_directory_and_zip_verification(self):
        result = split_model(self.model, self.source, self.folder, chunk_bytes=8)
        joined = b''.join(p.read_bytes() for p in sorted(self.folder.glob('*.part')))
        self.assertEqual(joined, self.payload)
        self.assertEqual(verify(self.root / 'app', self.data), result)
        archive = self.root / 'application.apk'
        with zipfile.ZipFile(archive, 'w') as z:
            for path in (self.root / 'app').rglob('*'):
                if path.is_file(): z.write(path, str(path.relative_to(self.root / 'app')))
        self.assertEqual(verify(archive, self.data)['sha256'], hashlib.sha256(self.payload).hexdigest())

    def test_corrupt_part_and_missing_part_are_rejected(self):
        split_model(self.model, self.source, self.folder, chunk_bytes=8)
        read = lambda name: (self.folder / name).open('rb')
        (self.folder / 'model-001.part').write_bytes(b'badbytes')
        with self.assertRaises(ValueError): verify_parts(read, self.model)
        (self.folder / 'model-001.part').unlink()
        with self.assertRaises(FileNotFoundError): verify_parts(read, self.model)

    def test_catalog_mismatch_and_false_included_flag_are_rejected(self):
        split_model(self.model, self.source, self.folder, chunk_bytes=8)
        (self.folder / 'catalog.json').write_text('{}')
        with self.assertRaises(ValueError): verify(self.root / 'app', self.data)
        (self.folder / 'bundle.json').write_text('{"format":"AMID_BUNDLED_MODEL","version":1,"included":false}')
        with self.assertRaises(ValueError): verify_parts(lambda n: (self.folder / n).open('rb'), self.model)

    def test_packaged_map_bytes_are_checked(self):
        split_model(self.model, self.source, self.folder, chunk_bytes=8)
        (self.folder.parent / 'world.geojson').write_text('{}')
        with self.assertRaises(ValueError): verify(self.root / 'app', self.data)

    def test_download_resume_and_range_ignoring_restart(self):
        target = self.root / 'cache/model.gguf'
        target.parent.mkdir()
        partial = target.with_suffix('.gguf.partial')
        partial.write_bytes(self.payload[:7])
        seen = []
        def resume(request, timeout):
            seen.append(request.get_header('Range'))
            return Response(self.payload[7:], 206,
                            {'Content-Range': f'bytes 7-{len(self.payload)-1}/{len(self.payload)}'})
        download(self.model, target, opener=resume)
        self.assertEqual(seen, ['bytes=7-'])
        self.assertEqual(target.read_bytes(), self.payload)
        target.unlink()
        partial.write_bytes(self.payload[:7])
        download(self.model, target, opener=lambda r, timeout: Response(self.payload))
        self.assertEqual(target.read_bytes(), self.payload)

    def test_bad_digest_cannot_enter_a_build(self):
        self.source.write_bytes(b'0' * len(self.payload))
        with self.assertRaises(ValueError): split_model(self.model, self.source, self.folder)
        target = self.root / 'cache.gguf'
        with self.assertRaises(ValueError):
            download(self.model, target, opener=lambda r, timeout: Response(b'0' * len(self.payload)))
        self.assertFalse(target.exists())
        self.assertFalse(target.with_suffix('.gguf.partial').exists())


if __name__ == '__main__':
    unittest.main()
