# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect corpus verdicts and evidence against partial output, stale binaries and process failures.

Exposes CorpusHarness for unittest discovery; test methods exercise the stated contracts.
"""
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from corpus_checks import compare_corpus, run_corpus
from corpus_crypto import run_crypto


# Exercise the shared process boundary independently of any protocol oracle or native compiler.
class CorpusHarness(unittest.TestCase):
    # Feature runners use the supplied process boundary and never run a stale binary after failed compilation.
    def test_feature_process_boundary(self):
        for build_code, run_code in ((1, 0), (0, 1), (0, 0)):
            # Exercise both failure stages and a successful structured report through the extracted entry point.
            with self.subTest(build=build_code, run=run_code):
                checks = SimpleNamespace(folder=Path('/fixture'),
                    build=Mock(return_value=({'exit_code': build_code}, Path('/fixture/driver'))),
                    command=Mock(return_value={'exit_code': run_code, 'output': '{"vectors": 12}'}))
                report = {}
                run_crypto('compiler', report, checks, {'crypto': 'production-library'})
                self.assertEqual(checks.build.call_args.args[-1], 'production-library')
                corpus = report['crypto_corpus']
                self.assertEqual(corpus['passed'], build_code == run_code == 0)
                if build_code:
                    # A previous executable at the requested path cannot satisfy a new failed build.
                    checks.command.assert_not_called()
                    self.assertNotIn('run', corpus)
                elif run_code:
                    # Failed execution retains diagnostics without promoting them into success counts.
                    self.assertNotIn('counts', corpus)
                else:
                    # Counts remain parsed evidence from the independent subprocess, not hard-coded values.
                    self.assertEqual(corpus['counts'], {'vectors': 12})

    # Exact complete rows and zero exit status are both mandatory, including suffix/empty-output cases.
    def test_verdicts_and_evidence(self):
        for output, code, complete, passed, mismatch in (
                ('one\ntwo\n', 0, True, True, None),
                ('one\n', 0, True, False, 1),
                ('one\ntwo\nextra\n', 0, True, False, 2),
                ('one\nwrong\n', 0, True, False, 1),
                ('', 0, True, False, 0),
                ('one\ntwo\n', 1, True, False, 2),
                ('one\ntwo\n', -6, True, False, 2),
                ('one\ntwo\n', 0, False, False, 2)):
            # Each isolated report retains its caller metadata and exact original execution arguments.
            with self.subTest(output=output, code=code, complete=complete):
                command = Mock(return_value=dict(exit_code=code, output=output, log='corpus.log'))
                corpus = dict(build=dict(exit_code=0), passed=False, requests=2, scope='fixture')
                compare_corpus(corpus, command, ['driver', 'requests.txt'], 'corpus',
                               ['one', 'two'], complete=complete)
                command.assert_called_once_with(['driver', 'requests.txt'], 'corpus')
                self.assertEqual(corpus['passed'], passed)
                self.assertEqual(corpus.get('first_mismatch'), mismatch)
                self.assertEqual(corpus['run'], dict(exit_code=code, log='corpus.log'))
                self.assertEqual(corpus['actual_sha256'], hashlib.sha256(output.encode()).hexdigest())
                self.assertEqual(corpus['expected_sha256'], hashlib.sha256(b'one\ntwo\n').hexdigest())
                self.assertEqual(corpus['scope'], 'fixture')
                self.assertEqual(corpus['requests'], 2)

    # A failed compile must never run a stale executable or invent successful-run evidence.
    def test_failed_build_does_not_execute(self):
        command = Mock()
        corpus = dict(build=dict(exit_code=1), passed=False, requests_sha256='retained')
        before = dict(corpus)
        compare_corpus(corpus, command, ['stale-driver'], 'corpus', ['one'])
        command.assert_not_called()
        self.assertEqual(corpus, before)

    # Process timeouts remain authoritative exceptions for the group's existing failure handler.
    def test_timeout_propagates(self):
        command = Mock(side_effect=subprocess.TimeoutExpired(['driver'], 180))
        corpus = dict(build=dict(exit_code=0), passed=False)
        with self.assertRaises(subprocess.TimeoutExpired):
            compare_corpus(corpus, command, ['driver'], 'corpus', ['one'])
        self.assertFalse(corpus['passed'])
        self.assertNotIn('run', corpus)

    # Freeze exact request bytes before compilation and forward linking, evidence and completeness unchanged.
    def test_setup_bytes_build_options_and_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)/'requests.txt'
            options = dict(crypto_library=Path('/crypto'), native_libraries=(Path('/bs'),),
                           defines=('integration',))
            metadata = dict(published_checks=7, scope='independent fixture')
            def compile_probe(*args, **kwargs):
                # The native compiler must see the same completed request file as the later driver.
                self.assertEqual(source.read_bytes(), 'alpha\nβ\n'.encode())
                return dict(exit_code=0), Path('/binary')
            build = Mock(side_effect=compile_probe)
            command = Mock(return_value=dict(exit_code=0, output='ok\n', log='retained.log'))
            corpus = run_corpus(build, command, 'compiler', 'driver.nim', 'build-name', source,
                                ['alpha', 'β'], ['ok'], 'run-name', metadata=metadata,
                                complete=False, **options)
            build.assert_called_once_with('compiler', 'driver.nim', 'build-name', **options)
            command.assert_called_once_with([Path('/binary'), source], 'run-name')
            self.assertFalse(corpus['passed'])
            self.assertEqual(corpus['requests'], 2)
            self.assertEqual(corpus['requests_sha256'], hashlib.sha256(source.read_bytes()).hexdigest())
            self.assertEqual(corpus['published_checks'], 7)
            self.assertEqual(metadata, dict(published_checks=7, scope='independent fixture'))

    # Failed builds retain request evidence and only the expected hashes historically emitted by that corpus.
    def test_setup_failed_build_hash_policy(self):
        with tempfile.TemporaryDirectory() as folder:
            for retain in (False, True):
                # Empty corpora still serialize their original trailing newline; stale drivers never execute.
                with self.subTest(expected_hash=retain):
                    source = Path(folder)/'requests.txt'
                    compiled = dict(exit_code=1, log='failed-build.log')
                    build = Mock(return_value=(compiled, Path('/stale-binary')))
                    command = Mock()
                    corpus = run_corpus(build, command, 'compiler', 'driver.nim', 'build-name',
                                        source, [], [], 'run-name', expected_hash=retain)
                    self.assertEqual(source.read_bytes(), b'\n')
                    self.assertEqual(corpus['build'], compiled)
                    self.assertFalse(corpus['passed'])
                    self.assertNotIn('actual_sha256', corpus)
                    self.assertEqual('expected_sha256' in corpus, retain)
                    if retain:
                        # The failed-build expected hash uses the same newline convention as successful runs.
                        self.assertEqual(corpus['expected_sha256'], hashlib.sha256(b'\n').hexdigest())
                    command.assert_not_called()
