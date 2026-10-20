# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify build identity overrides, source provenance and stable generated Nim literals."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import build_info


# Temporary roots isolate packaging metadata and never change the developer's repository.
class BuildInfoTests(unittest.TestCase):
    # Release labels are escaped byte-for-byte and unchanged metadata preserves compiler caches.
    def test_overrides_and_stable_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'spec').mkdir()
            (root/'src').mkdir()
            (root/'src/version.json').write_text('{"version":"development"}')
            pins = {'version': '0.6.3', 'commit': '5b51edfedb4d0dbd9028d9e57ac61d69dffe9410'}
            (root/'spec/toolchain.json').write_text(json.dumps(pins))
            environment = {'RAGNAROK_VERSION': '1.2.3-rc1"\\', 'RAGNAROK_REVISION': 'a' * 40,
                           'SOURCE_DATE_EPOCH': '0'}
            with patch.object(build_info, 'revision', side_effect=AssertionError('unexpected Git lookup')):
                values = build_info.build(root, environment)
                output = root/'build/build_info.nim'
                initial = output.stat().st_mtime_ns
                self.assertEqual(values['CompilerRevision'], pins['commit'])
                self.assertEqual(values['BuildTimestamp'], '1970-01-01T00:00:00Z')
                self.assertEqual(values['AppVersion'], environment['RAGNAROK_VERSION'])
                self.assertIn('\\x22\\x5c', output.read_text())
                build_info.build(root, environment)
                self.assertEqual(initial, output.stat().st_mtime_ns)
                environment['RAGNAROK_VERSION'] = '1.2.3'
                build_info.build(root, environment)
                self.assertNotIn('\\x22\\x5c', output.read_text())

    # Development labels retain actual source identity; missing archive Git data is explicit.
    def test_default_and_archive_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'spec').mkdir()
            (root/'src').mkdir()
            (root/'src/version.json').write_text('{"version":"development"}')
            (root/'spec/toolchain.json').write_text('{"version":"0.6.3","commit":"abc"}')
            with patch.object(build_info, 'revision', return_value='abc-dirty'):
                values = build_info.build(root, {'SOURCE_DATE_EPOCH': '0'})
            self.assertEqual(values['AppVersion'], 'development')
            self.assertEqual(values['AppRevision'], 'abc-dirty')
            for error in (FileNotFoundError('git'), subprocess.CalledProcessError(128, ['git'])):
                # An archive remains buildable whether Git is absent or reports no repository.
                with patch.object(build_info.subprocess, 'check_output', side_effect=error):
                    self.assertEqual(build_info.revision(root), 'unknown')

    # The checked-in application file supplies the version when no release override is requested.
    def test_version_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'spec').mkdir()
            (root/'src').mkdir()
            (root/'spec/toolchain.json').write_text('{"version":"0.6.3","commit":"abc"}')
            version = root/'src/version.json'
            version.write_text('{"version":"1.2.3"}')
            environment = {'RAGNAROK_REVISION': 'abc', 'SOURCE_DATE_EPOCH': '0'}
            self.assertEqual(build_info.build(root, environment)['AppVersion'], '1.2.3')
            version.write_text('{"version":"1.2.4"}')
            self.assertEqual(build_info.build(root, environment)['AppVersion'], '1.2.4')

    # Build time is UTC and reproducible overrides cannot silently wrap or accept invalid text.
    def test_timestamp(self):
        self.assertEqual(build_info.timestamp({'SOURCE_DATE_EPOCH': '1'}), '1970-01-01T00:00:01Z')
        self.assertRegex(build_info.timestamp({}), r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')
        for value in ('', '-1', '1.5', 'tomorrow', '253402300800'):
            # Invalid overrides must fail compilation preparation instead of changing provenance.
            with self.subTest(value=value), self.assertRaises(ValueError):
                build_info.timestamp({'SOURCE_DATE_EPOCH': value})

    # Archives nested under unrelated repositories must not report the parent application's commit.
    def test_archive_inside_another_checkout(self):
        with patch.object(build_info.subprocess, 'check_output', return_value='/unrelated/repository\n'):
            self.assertEqual(build_info.revision(ROOT), 'unknown')

    # Clean builds identify HEAD exactly; edits must never claim a pristine source revision.
    def test_git_dirty_marker(self):
        for status, expected in (('', 'a' * 40), (' M src/ragnarok.nim\n', 'a' * 40 + '-dirty')):
            # Both status variants use the same full compiler-independent source revision.
            with self.subTest(status=status), patch.object(build_info.subprocess, 'check_output',
                                                           side_effect=[str(ROOT) + '\n', 'a' * 40 + '\n', status]):
                self.assertEqual(build_info.revision(ROOT), expected)

    # Invalid packaging values fail the build instead of introducing multiline or ambiguous identities.
    def test_reject_invalid_labels(self):
        for value in (None, 123, '', 'x' * 129, 'release\n', 'release\x00', 'release\x7f', 'rélease'):
            # Every invalid byte class has the same bounded identity contract.
            with self.subTest(value=value), self.assertRaises(ValueError):
                build_info.checked(value)


# Standalone execution matches ordinary Make Python discovery without preparing native dependencies.
if __name__ == '__main__':
    unittest.main()
