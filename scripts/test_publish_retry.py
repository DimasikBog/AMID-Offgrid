import hashlib
import unittest
import urllib.error

from publish_candidate import upload_asset


class PublishRetryTests(unittest.TestCase):
    def test_transient_failure_without_asset_retries_boundedly(self):
        posts, pauses = [], []

        def api(path, **kwargs):
            if kwargs.get('method') == 'POST':
                posts.append(path)
                if len(posts) == 1:
                    raise urllib.error.HTTPError(path, 500, 'temporary', {}, None)
                return {'id': 4}
            return []

        self.assertEqual(upload_asset(api, 1, 'app.zip', b'content', sleep=pauses.append), {'id': 4})
        self.assertEqual(len(posts), 2)
        self.assertEqual(pauses, [2])

    def test_completed_ambiguous_upload_is_verified_without_second_post(self):
        data = b'content'
        posts = []

        def api(path, **kwargs):
            if kwargs.get('method') == 'POST':
                posts.append(path)
                raise urllib.error.HTTPError(path, 502, 'temporary', {}, None)
            return [{'id': 7, 'name': 'app.zip', 'state': 'uploaded', 'size': len(data),
                     'digest': 'sha256:' + hashlib.sha256(data).hexdigest()}]

        self.assertEqual(upload_asset(api, 1, 'app.zip', data, sleep=lambda _: None)['id'], 7)
        self.assertEqual(len(posts), 1)

    def test_only_zero_byte_starter_is_removed_before_retry(self):
        calls = []

        def api(path, **kwargs):
            calls.append((path, kwargs.get('method')))
            if kwargs.get('method') == 'POST':
                if len(calls) == 1:
                    raise urllib.error.HTTPError(path, 500, 'temporary', {}, None)
                return {'id': 8}
            if kwargs.get('method') == 'DELETE':
                return None
            return [{'id': 7, 'name': 'app.zip', 'state': 'starter', 'size': 0}]

        upload_asset(api, 1, 'app.zip', b'content', sleep=lambda _: None)
        self.assertIn(('/releases/assets/7', 'DELETE'), calls)

    def test_wrong_hash_and_auth_errors_never_get_deleted_or_retried(self):
        for kind in ['hash', 'auth']:
            calls = []

            def api(path, **kwargs):
                calls.append(kwargs.get('method'))
                if kwargs.get('method') == 'POST':
                    raise urllib.error.HTTPError(path, 403 if kind == 'auth' else 500, 'error', {}, None)
                return [{'id': 7, 'name': 'app.zip', 'state': 'uploaded', 'size': 7, 'digest': 'sha256:wrong'}]

            expected = urllib.error.HTTPError if kind == 'auth' else ValueError
            with self.assertRaises(expected):
                upload_asset(api, 1, 'app.zip', b'content', sleep=lambda _: None)
            self.assertEqual(calls.count('POST'), 1)
            self.assertNotIn('DELETE', calls)

    def test_retry_limit_leaves_an_unpublished_failure(self):
        posts = []

        def api(path, **kwargs):
            if kwargs.get('method') == 'POST':
                posts.append(path)
                raise urllib.error.HTTPError(path, 503, 'temporary', {}, None)
            return []

        with self.assertRaises(urllib.error.HTTPError):
            upload_asset(api, 1, 'app.zip', b'content', sleep=lambda _: None, attempts=3)
        self.assertEqual(len(posts), 3)


if __name__ == '__main__':
    unittest.main()
