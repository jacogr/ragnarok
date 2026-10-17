"""Protect corpus verdicts and evidence against partial output, stale binaries and process failures."""
import hashlib
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from corpus_checks import compare_corpus


# Exercise the shared process boundary independently of any protocol oracle or native compiler.
class CorpusHarness(unittest.TestCase):
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
