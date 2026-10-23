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

    def test_current_sequence_consumers_share_build_and_reject_failure(self):
        """One witness build serves all modes; a failed build prevents every live observation."""
        import hashlib
        from unittest.mock import Mock, patch
        from harness_fixtures import temporary_folder
        import e2e_checks
        consumers = (
            ('application_current_sequence', 'observe'),
            ('application_current_preimages', 'observe_preimages'),
            ('application_current_guarantees', 'observe_guarantees'),
            ('application_current_rotated', 'observe_rotated'))
        with temporary_folder('input') as folder:
            fixture = (None, {}, ((folder/'input', hashlib.sha256(b'').hexdigest()),))
            for peer_code, witness_code in ((1, 0), (0, 1), (0, 0)):
                # Exercise real prerequisite scheduling and all consumers without starting native processes.
                checks = SimpleNamespace(folder=folder,
                    build=Mock(return_value=({'exit_code': witness_code}, folder/'responder')))
                context = SimpleNamespace(current_download_peer=({'exit_code': peer_code}, folder/'peer'),
                    compiler=folder/'compiler', crypto=folder/'crypto', bs=folder/'bs', quic=folder/'quic',
                    certificates=folder/'certificates', checks=checks)
                e2e_checks.prepare_current_sequence_responder(context)
                for workload, observer in consumers:
                    with self.subTest(peer=peer_code, witness=witness_code, workload=workload), patch(
                            'native_fixtures.unit_runtime_fixtures',
                            side_effect=lambda *args, suite: {suite: fixture}) as fixtures, patch(
                            'application_current_sequence.'+observer,
                            return_value={'passed': True}) as observe, patch('e2e_checks.announce'):
                        result = getattr(e2e_checks, workload)(context)
                        self.assertEqual(result['passed'], peer_code == witness_code == 0)
                        if peer_code == witness_code == 0:
                            # Every mode still binds its own fixture contract and fresh work directory.
                            fixtures.assert_called_once()
                            observe.assert_called_once()
                            self.assertEqual(observe.call_args.args[:2], (folder/'peer', folder/'responder'))
                            self.assertEqual(result['build'], context.current_sequence_responder[0])
                        else:
                            fixtures.assert_not_called()
                            observe.assert_not_called()
                if peer_code:
                    checks.build.assert_not_called()
                else:
                    checks.build.assert_called_once()
                    self.assertEqual(checks.build.call_args.args[1],
                        ROOT/'tests/native/application_current_sequence.nim')

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

    def test_cli_group_scope_and_standalone_fixture_preparation(self):
        """Full and selected CLI runs prepare only consumed wires and serialize their actual scope."""
        import json
        import os
        from unittest.mock import patch
        from harness_fixtures import temporary_folder
        from e2e_checks import PLAN

        def observed(*arguments, group):
            """Substitute native execution only; report all expected verdicts from the selected plan."""
            report = arguments[6]
            selected = PLAN.select(group)
            report['suites'] = [dict(name=name, passed=True) for name in selected.names('selftest')]
            report.update({name: dict(passed=True) for name in selected.names('workload')})

        with temporary_folder() as folder:
            wires = folder/'wires'
            wires.mkdir()
            for index in range(8):
                # Tiny inert inputs suffice to exercise CLI fixture hashes without a native producer.
                (wires/f'{index}.bin').write_bytes(bytes([index]))
            for group in (None, *PLAN.groups()):
                arguments = ['test_e2e.py', '--compiler', str(folder/'compiler/nimony')]
                output = folder/'e2e'
                if group is not None:
                    arguments += ['--group', group]
                if group == 'offload':
                    # A selected ThinLTO trial must retain its explicit mode and private output root.
                    output = folder/'thin-e2e'
                    arguments += ['--lto', 'thin', '--build-dir', str(output)]
                with self.subTest(group=group), patch('sys.argv', arguments), patch.dict(
                        os.environ, E2E_GROUP=''), patch('test_e2e.ROOT', folder), patch(
                        'test_e2e.BUILD', folder/'e2e'), patch(
                        'test_e2e.runtime_sources', return_value=[]), patch(
                        'native_checks.NativeChecks.command', return_value=dict(output='head', exit_code=0)), patch(
                        'nimony_crypto.prepare', return_value=(folder/'crypto', None, {})), patch(
                        'bandersnatch_native.prepare', return_value=(folder/'bs', None, {})), patch(
                        'nimony_quic.prepare', return_value=(folder/'quic', folder/'certificates', {})), patch(
                        'test_integration.BUILD', folder/'integration'), patch(
                        'test_integration.corpus', return_value=(wires, {})) as corpus, patch(
                        'test_e2e.run', side_effect=observed) as run:
                    with self.assertRaises(SystemExit) as result:
                        test_e2e.main()
                    self.assertEqual(result.exception.code, 0)
                    self.assertEqual(run.call_args.kwargs['group'], group)
                    report = json.loads((output/'results.json').read_text())
                    self.assertEqual(report['e2e_group'], group)
                    self.assertEqual(report['e2e_lto'], 'thin' if group == 'offload' else 'full')
                    self.assertTrue(test_e2e.passed(report))
                    if group in (None, 'transport'):
                        corpus.assert_called_once()
                        self.assertEqual(len(report['fixture_sha256']), 8)
                    else:
                        corpus.assert_not_called()
                        self.assertNotIn('fixture_sha256', report)

    def test_groups_partition_all_verdicts_and_require_complete_scope(self):
        """All workloads/selftests belong to exactly one group; setup builds only its consumers' profiles."""
        from e2e_checks import PLAN
        from summarize_tests import summarize
        workloads, selftests = [], []
        prerequisites = {
            'application': ('prepare_peer',),
            'current': ('prepare_current_download_peer', 'prepare_current_sequence_responder'),
            'offload': ('prepare_offload_peer',),
            'telemetry': ('prepare_peer',),
            'transport': ('prepare_peer', 'prepare_integrated_peer')}
        for group in PLAN.groups():
            selected = PLAN.select(group)
            names, suites = selected.names('workload'), selected.names('selftest')
            workloads.extend(names)
            selftests.extend(suites)
            with self.subTest(group=group):
                self.assertEqual(selected.names('setup'), prerequisites[group])
                report = dict(status='checks-passed', e2e_group=group,
                    suites=[dict(name=name, passed=True) for name in suites],
                    **{name: dict(passed=True) for name in names})
                self.assertTrue(test_e2e.passed(report))
                # Summary rendering uses a real failed report to avoid fabricating resource observations.
                self.assertIn('Scope: **'+group+'**', summarize(dict(
                    status='failed', e2e_group=group, suites=[]), 'e2e'))
                self.assertFalse(test_e2e.passed({**report, 'e2e_group': None}))
                self.assertFalse(test_e2e.passed({**report, 'e2e_group': 'typo'}))
                for name in names:
                    # Every scenario remains mandatory; no passing sibling fills an omitted verdict.
                    missing = dict(report)
                    del missing[name]
                    self.assertFalse(test_e2e.passed(missing))
                    self.assertFalse(test_e2e.passed({**report, name: dict(passed=False)}))
                for name in suites:
                    missing = dict(report, suites=[row for row in report['suites'] if row['name'] != name])
                    self.assertFalse(test_e2e.passed(missing))
                foreign = next(name for name in test_e2e.WORKLOADS if name not in names)
                self.assertFalse(test_e2e.passed({**report, foreign: dict(passed=True)}))
        self.assertCountEqual(workloads, test_e2e.WORKLOADS)
        self.assertEqual(len(workloads), len(set(workloads)))
        self.assertCountEqual(selftests, test_e2e.SELFTESTS)
        self.assertEqual(len(selftests), len(set(selftests)))

    def test_download_workloads_refuse_failed_peer_or_witness_build(self):
        """Stale executable/witness binaries cannot satisfy each independent download workload."""
        from unittest.mock import Mock, patch
        import e2e_checks
        for workload in ('application_download_sequence', 'application_remote_ancestors', 'application_discovery_ancestors'):
            for peer_code in (0, 1):
                # Each declared workload must own its build failure and skip process observation entirely.
                checks = SimpleNamespace(folder=ROOT/'build/tests/e2e',
                    build=Mock(return_value=({'exit_code': 1}, Path('/stale-responder'))))
                context = SimpleNamespace(peer=({'exit_code': peer_code}, Path('/stale-peer')),
                    compiler=Path('/compiler'), crypto=Path('/crypto'), bs=Path('/bandersnatch'),
                    quic=Path('/quic'), checks=checks)
                observer_module = 'application_remote_ancestors' if workload == 'application_discovery_ancestors' else workload
                with self.subTest(workload=workload, peer_code=peer_code), patch(
                        'e2e_checks.announce'), patch(observer_module+'.observe') as observe:
                    self.assertFalse(getattr(e2e_checks, workload)(context)['passed'])
                    observe.assert_not_called()
                    if peer_code:
                        checks.build.assert_not_called()
                    else:
                        checks.build.assert_called_once()
                        self.assertEqual(checks.build.call_args.args[1],
                                         ROOT/('tests/native/'+observer_module+'.nim'))


# Direct execution uses the same safeguards as normal unittest discovery.
if __name__ == '__main__':
    unittest.main()
