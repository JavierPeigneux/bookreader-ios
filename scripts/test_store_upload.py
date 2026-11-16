import tempfile
from pathlib import Path
import hashlib
import unittest
from unittest.mock import Mock, patch
import store_upload as store

class StoreUploadTests(unittest.TestCase):
    def test_british_primary_uses_prepared_english_without_mutating_source(self):
        metadata = {'localizations': {'en-US': {'description': 'English'}, 'es-ES': {'description': 'Castellano'}}}
        copies = store.localized_copy(metadata, 'en-GB')
        self.assertEqual(copies['en-GB'], metadata['localizations']['en-US'])
        self.assertNotIn('en-GB', metadata['localizations'])
        metadata['localizations']['en-GB'] = {'description': 'Custom British copy'}
        self.assertEqual(store.localized_copy(metadata, 'en-GB')['en-GB']['description'], 'Custom British copy')

    def test_complete_identical_image_is_reused(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)/'01-library.jpg'; p.write_bytes(b'screenshot')
            existing = {'id': 'existing', 'attributes': {'sourceFileChecksum': hashlib.md5(p.read_bytes()).hexdigest(), 'assetDeliveryState': {'state': 'COMPLETE'}}}
            api = Mock()
            with patch.object(store, 'wait_asset', return_value=existing) as wait:
                self.assertEqual(store.upload_image(api, 'set', p, [existing]), existing)
            api.save.assert_not_called()
            wait.assert_called_once_with(api, 'existing')

    def test_incomplete_local_assets_fail_before_remote_changes(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(store, 'ROOT', Path(directory)):
            api = Mock()
            with self.assertRaisesRegex(ValueError, 'Missing screenshot'):
                store.upload(api, '1.0')
            api.call.assert_not_called()

    def test_failed_processing_is_not_reported_as_success(self):
        api = Mock()
        api.call.return_value = {'data': {'attributes': {'assetDeliveryState': {'state': 'FAILED'}}}}
        with self.assertRaisesRegex(RuntimeError, 'could not process'):
            store.wait_asset(api, 'bad')

    def test_credentials_missing_fail_without_exposing_keys(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(store, 'ROOT', Path(directory)), patch.dict(store.os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, 'Missing ASC_KEY_PATH'):
                store.credentials()

if __name__ == '__main__':
    unittest.main()
