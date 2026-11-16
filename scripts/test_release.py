import contextlib
import io
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import release


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.version = self.root / 'version.json'
        self.version.write_text('{"version":"1.0.0","build":7}')
        self.project = self.root / 'project.xcproj'
        self.project.write_text('{"MARKETING_VERSION":"1.0.0","CURRENT_PROJECT_VERSION":"7",}')
        for name, value in [('ROOT', self.root), ('RELEASE', self.root), ('VERSION', self.version), ('PROJECTS', [self.project])]:
            patcher = patch.object(release, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def invoke(self, *args, failure=None):
        with patch('sys.argv', ['release.py', *args]), patch.object(release, 'preflight'), \
             patch.object(release, 'settings', return_value={}), patch.object(release, 'auth_args', return_value=[]), \
             patch.object(release, 'run', side_effect=failure) as run, contextlib.redirect_stdout(io.StringIO()):
            release.main()
            return run

    def test_archive_advances_version_without_upload(self):
        run = self.invoke('archive')
        self.assertEqual(json.loads(self.version.read_text()), {'version': '1.0.1', 'build': 8})
        self.assertIn('"MARKETING_VERSION":"1.0.1"', self.project.read_text())
        self.assertTrue(any('archive' in call.args[0] for call in run.call_args_list))
        self.assertFalse(any('-exportArchive' in call.args[0] for call in run.call_args_list))

    def test_rebuild_keeps_store_version_and_advances_build(self):
        self.invoke('archive', '--version', '1.0', '--rebuild')
        self.assertEqual(json.loads(self.version.read_text()), {'version': '1.0', 'build': 8})

    def test_failed_build_reserves_number(self):
        with self.assertRaises(OSError):
            self.invoke('archive', failure=OSError('build failed'))
        self.assertEqual(json.loads(self.version.read_text())['build'], 8)
        self.invoke('archive')
        self.assertEqual(json.loads(self.version.read_text())['build'], 9)

    def test_existing_archive_upload_keeps_version(self):
        archive = self.root / 'Existing.xcarchive'
        archive.mkdir()
        (archive / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': {'CFBundleIdentifier': 'com.javierpeigneux.Folisona'}}))
        run = self.invoke('upload', '--archive', str(archive))
        self.assertEqual(json.loads(self.version.read_text())['build'], 7)
        self.assertIn('-exportArchive', run.call_args.args[0])
        options = plistlib.loads((self.root / 'Exports/Existing/ExportOptions.plist').read_bytes())
        self.assertEqual(options['destination'], 'upload')
        self.assertTrue(options['manageAppVersionAndBuildNumber'])

    def test_rejects_archive_with_previous_bundle_identifier(self):
        archive = self.root / 'Previous.xcarchive'
        archive.mkdir()
        (archive / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': {'CFBundleIdentifier': 'com.javierpeigneux.Bookreader'}}))
        with self.assertRaisesRegex(ValueError, 'Archive does not belong to Folisona'):
            self.invoke('upload', '--archive', str(archive))
        self.assertFalse((self.root / 'Exports').exists())
        self.assertEqual(json.loads(self.version.read_text())['build'], 7)

    def test_distribution_export_does_not_upload_or_increment(self):
        archive = self.root / 'Existing.xcarchive'
        archive.mkdir()
        (archive / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': {'CFBundleIdentifier': 'com.javierpeigneux.Folisona'}}))
        run = self.invoke('export', '--archive', str(archive))
        self.assertEqual(json.loads(self.version.read_text())['build'], 7)
        options = plistlib.loads((self.root / 'Exports/Existing/ExportOptions.plist').read_bytes())
        self.assertEqual(options['method'], 'app-store-connect')
        self.assertEqual(options['destination'], 'export')
        self.assertEqual(options['signingStyle'], 'automatic')
        self.assertFalse(options['manageAppVersionAndBuildNumber'])
        self.assertIn('-allowProvisioningUpdates', run.call_args.args[0])

    def test_malformed_project_does_not_consume_version(self):
        self.project.write_text('{}')
        with self.assertRaises(ValueError):
            self.invoke('archive')
        self.assertEqual(json.loads(self.version.read_text())['build'], 7)

    def test_rejects_older_or_malformed_version_without_mutation(self):
        for version in ['0.9.9', '1.0.0', '1', '1.2.3;echo unsafe']:
            with self.assertRaises(ValueError):
                self.invoke('archive', '--version', version)
            self.assertEqual(json.loads(self.version.read_text())['build'], 7)


if __name__ == '__main__':
    unittest.main()
