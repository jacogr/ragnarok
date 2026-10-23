# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Local artifact admission refuses executable substitution and never imports execution authority."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import paired_storage_reopens as paired
from test_compare_storage_reopens import fixture


class PairedAdmissionTests(unittest.TestCase):
    """Inert native headers are enough to test admission; no selected fixture is ever executed."""

    def setUp(self):
        """Author independently validated reports and explicit local artifact selections."""
        self.temporary = tempfile.TemporaryDirectory(prefix='paired-test-', dir=ROOT/'build')
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.report = fixture()
        self.config = dict(schema_version=1, allow_sources=[])
        for label in paired.LABELS:
            binary = self.folder/(label+'-native')
            binary.write_bytes(b'\x7fELF inert test fixture'); binary.chmod(0o700)
            report = copy.deepcopy(self.report)
            report['native_binary_sha256'] = paired.sha256(binary)
            path = self.folder/(label+'.json'); path.write_text(json.dumps(report))
            self.config[label] = dict(binary=str(binary), report=str(path))
        self.provider = patch.object(paired, 'provider_hashes', return_value=self.report['inputs']['native_components'])
        self.provider.start(); self.addCleanup(self.provider.stop)

    def test_explicit_artifacts_and_inert_reports(self):
        reports, binaries = paired.admit(self.config)
        self.assertEqual(set(reports), set(paired.LABELS))
        self.assertEqual(binaries['baseline'], Path(self.config['baseline']['binary']))

    def test_substituted_binary_provider_and_observer_refuse(self):
        for kind in ('binary', 'provider', 'observer', 'interpreter'):
            # Each substitution changes an execution boundary independently of descriptive input metadata.
            with self.subTest(kind=kind):
                path = Path(self.config['candidate']['report'])
                original = path.read_text(); report = json.loads(original)
                if kind == 'binary': report['native_binary_sha256'] = 'f'*64
                elif kind == 'provider': report['inputs']['native_components']['bridge'] = 'f'*64
                elif kind == 'observer': report['inputs']['sources']['tools/storage_fresh_reopen.py'] = 'f'*64
                else: report['inputs']['python_identity']['executable'] = '/different/python'
                path.write_text(json.dumps(report))
                with self.assertRaises(ValueError): paired.admit(self.config)
                path.write_text(original)

    def test_symlink_escape_and_non_native_refuse(self):
        target = Path(self.config['candidate']['binary'])
        alias = self.folder/'alias'; alias.symlink_to(target)
        with self.assertRaisesRegex(ValueError, 'symlink'): paired.local_artifact(str(alias))
        with self.assertRaisesRegex(ValueError, 'below build'): paired.local_artifact('/bin/sh')
        target.write_bytes(b'#!/bin/sh\nexit 0\n')
        report_path = Path(self.config['candidate']['report'])
        report = json.loads(report_path.read_text()); report['native_binary_sha256'] = paired.sha256(target)
        report_path.write_text(json.dumps(report))
        with self.assertRaisesRegex(ValueError, 'native ELF'): paired.admit(self.config)

    def test_bounded_exact_configuration(self):
        path = self.folder/'config.json'; path.write_text(json.dumps(self.config))
        self.assertEqual(paired.read_config(path), self.config)
        for change in ({'schema_version': True}, {'command': ['/bin/sh']}, {'allow_sources': ['x','x']}):
            # Configuration selects artifacts and source identities only; no executable argument vector is accepted.
            path.write_text(json.dumps(dict(self.config, **change)))
            with self.assertRaises(ValueError): paired.read_config(path)
        path.write_bytes(b'x'*20)
        with patch.object(paired, 'MAX_CONFIG_BYTES', 10), self.assertRaisesRegex(ValueError, '64 KiB'):
            paired.read_config(path)

    def fake_command(self, argv, name, folder, timeout):
        """Author native witnesses independently; subprocess dispatch is intercepted before any execution."""
        self.commands.append(argv)
        if argv[1] == 'prepare':
            engine, count = argv[2], int(argv[3])
            row = next(r for r in self.report['rows'] if r['case'] == [engine,count])
            raw = row['prepared_raw']
        else:
            engine, count = argv[5], int(argv[6])
            row = next(r for r in self.report['rows'] if r['case'] == [engine,count])
            raw = row['raw']; Path(argv[2]).write_text(json.dumps(row['resources']))
        log = folder/(name+'.log'); log.write_text(raw)
        return dict(command=argv, exit_code=0, elapsed_seconds=0.01, log=str(log))

    def test_collector_fixed_order_and_explicit_execution(self):
        output = self.folder/'pair'
        with self.assertRaisesRegex(ValueError, 'execute-local-builds'):
            paired.collect(self.config, output)
        self.commands = []
        def selected(path):
            """Selected names depend on the source-owned backend identity, never an imported command."""
            engine = 'managed' if 'managed' in str(path) else 'journal'
            return next(r['selected_before'] for r in self.report['rows'] if r['case'][0] == engine)
        with patch.object(paired, 'command', side_effect=self.fake_command), \
             patch.object(paired, 'selected_hashes', side_effect=selected), \
             patch.object(paired, 'environment', return_value=self.report['environment']):
            report = paired.collect(self.config, output, execute_local_builds=True)
        self.assertEqual(report['status'], 'checks-passed')
        self.assertEqual(len(self.commands), 24); self.assertEqual(len(report['rows']), 16)
        self.assertEqual([r['binary'] for r in report['rows'][:2]], ['baseline','candidate'])
        self.assertEqual([r['binary'] for r in report['rows'][8:10]], ['candidate','baseline'])
        self.assertEqual(report['rows'][0]['count'], 32768)
        self.assertEqual(report['rows'][8]['count'], 131072)
        self.assertFalse(any(p.is_dir() for p in output.iterdir()))
        with self.assertRaises(FileExistsError): paired.output_folder(output)

    def test_failed_collection_is_incomplete_and_retires_namespace(self):
        output = self.folder/'failed-pair'
        def failed(argv, name, folder, timeout):
            """A real process failure cannot leave a successful report or selected temporary namespace."""
            return dict(command=argv, exit_code=2, elapsed_seconds=0.01, log=str(folder/'failed.log'))
        with patch.object(paired, 'command', side_effect=failed), \
             patch.object(paired, 'environment', return_value=self.report['environment']):
            with self.assertRaisesRegex(ValueError, 'producer failed'):
                paired.collect(self.config, output, execute_local_builds=True)
        report = json.loads((output/'results.json').read_text())
        self.assertEqual(report['status'], 'failed'); self.assertEqual(report['rows'], [])
        self.assertFalse((output/'summary.md').exists())
        self.assertFalse(any(p.is_dir() for p in output.iterdir()))


if __name__ == '__main__':
    unittest.main()
