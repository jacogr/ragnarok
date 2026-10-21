# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check E2E workload completeness and disjoint suite ownership.

Exposes VerificationE2E for unittest discovery; test methods exercise the stated contracts.
"""
from pathlib import Path
import sys
import unittest
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import test_e2e
from native_tests import UNIT_SUITES


# Keep e2e ownership and failure safeguards independent of other verification groups.
class VerificationE2E(unittest.TestCase):
    def test_peer_builds_link_download_dependencies(self):
        """Every executable shape needs the bootstrap crypto ABI, regardless of offload defines."""
        from e2e_checks import prepare_peer, prepare_integrated_peer
        from native_checks import NativeChecks
        from unittest.mock import patch
        context = SimpleNamespace(compiler=Path('/compiler'), crypto=Path('/crypto/library'),
                                  bs=Path('/bandersnatch/library'), quic=Path('/quic/library'),
                                  report={}, checks=NativeChecks(ROOT/'build/tests/e2e'))
        for prepare in (prepare_peer, prepare_integrated_peer):
            # Exercise the actual build planner; capture commands before launching the compiler.
            with self.subTest(prepare=prepare.__name__), patch.object(
                    context.checks, 'command', return_value={'exit_code': 0}) as command:
                prepare(context)
                arguments = command.call_args.args[0]
                self.assertIn('--passC:-I'+str(ROOT/'native/bandersnatch'), arguments)
                self.assertIn('--passL:'+str(context.bs), arguments)

    # Every E2E workload and CLI selftest is required, including on a fresh standalone invocation.
    def test_e2e_complete_inventory(self):
        report = dict(suites=[dict(name=name, passed=True) for name in test_e2e.SELFTESTS],
                      **{name: dict(passed=True) for name in test_e2e.WORKLOADS})
        self.assertTrue(test_e2e.passed(report))
        for name in test_e2e.WORKLOADS:
            # A successful sibling cannot stand in for a missing or failed lifecycle.
            with self.subTest(workload=name):
                missing = dict(report)
                del missing[name]
                self.assertFalse(test_e2e.passed(missing))
                missing[name] = dict(passed=False)
                self.assertFalse(test_e2e.passed(missing))
        self.assertFalse(test_e2e.passed({**report, 'suites': []}))
        self.assertFalse(test_e2e.passed({**report, 'suites': report['suites']+[report['suites'][0]]}))
        self.assertFalse(test_e2e.passed({**report, 'suites': [dict(name='replacement', passed=True)]+report['suites'][1:]}))
        self.assertFalse(set(UNIT_SUITES) & set(test_e2e.SELFTESTS))

    def test_download_workloads_refuse_failed_peer_or_witness_build(self):
        """Stale executable/witness binaries cannot satisfy either independent download workload."""
        from unittest.mock import Mock, patch
        import e2e_checks
        for workload in ('application_download_sequence', 'application_remote_ancestors'):
            for peer_code in (0, 1):
                # Each declared workload must own its build failure and skip process observation entirely.
                checks = SimpleNamespace(folder=ROOT/'build/tests/e2e',
                    build=Mock(return_value=({'exit_code': 1}, Path('/stale-responder'))))
                context = SimpleNamespace(peer=({'exit_code': peer_code}, Path('/stale-peer')),
                    compiler=Path('/compiler'), crypto=Path('/crypto'), bs=Path('/bandersnatch'),
                    quic=Path('/quic'), checks=checks)
                with self.subTest(workload=workload, peer_code=peer_code), patch(
                        'e2e_checks.announce'), patch(workload+'.observe') as observe:
                    self.assertFalse(getattr(e2e_checks, workload)(context)['passed'])
                    observe.assert_not_called()
                    if peer_code:
                        checks.build.assert_not_called()
                    else:
                        checks.build.assert_called_once()
                        self.assertEqual(checks.build.call_args.args[1],
                                         ROOT/('tests/native/'+workload+'.nim'))


# Direct execution uses the same safeguards as normal unittest discovery.
if __name__ == '__main__':
    unittest.main()
