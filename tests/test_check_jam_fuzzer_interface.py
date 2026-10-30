# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""The opt-in JAM interface group fails closed and never claims live engine campaign validation."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import check_jam_fuzzer_interface as interface
from jam_fuzz_corpora import CORPORA
from workflow_fixtures import job_section, commands, artifact_paths


class JamInterfaceCI(unittest.TestCase):
    """Check completeness, stale-report retirement and independently gated CI matrix families."""

    def complete(self):
        """A complete synthetic verdict includes every source-owned interface case and real-entry workload."""
        from jam_minifuzz_plan import expectations
        declared = expectations()
        sessions = sum(row['sessions'] for row in declared)
        imports = sum(row['signed_imports'] for row in declared)
        exchanges = sum(row['exchanges'] for row in declared)
        controls = {field:sum(row['controls'][field] for row in declared) for field in declared[0]['controls']}
        outcomes = {field:sum(row[field] for row in declared) for field in ('accepted_imports','refused_imports')}
        observed = [dict(reference=row['reference'],**{field:row[field] for field in outcomes}) for row in declared]
        references = [dict(reference=row['reference'],fixture_sha256=row['fixture_sha256'],
                           expected_sha256=row['expected_sha256'] or 'a'*64,
                           sessions=row['sessions'],signed_imports=row['signed_imports'],
                           **{field:row[field] for field in outcomes}) for row in declared]
        return dict(cases={name: dict(passed=True, build=dict(exit_code=0), run=dict(exit_code=0),
                                     expected_sha256='a'*64, actual_sha256='a'*64) for name in interface.CASES},
                    socket=dict(passed=True, guests=dict(passed=True, sessions=2, signed_imports=3,
                        guest_siblings=1, expected_state_queries=11, completed_sessions=2,
                        completed_imports=3, retained_siblings=1, complete_state_queries=11,
                        consensus_rejections=3, isolated_reconnects=1)),
                    minifuzz=dict(passed=True, false_success_control=True,observed_references=observed,
                        **{prefix+field:count for prefix in ('planned_','completed_') for field,count in outcomes.items()}, planned_sessions=sessions,
                        completed_sessions=sessions, planned_exchanges=exchanges, completed_exchanges=exchanges, signed_imports=imports,
                        independent_references=references,
                        planned_local_missing_evidence=controls['local_missing_evidence'], completed_local_missing_evidence=controls['local_missing_evidence'],
                        planned_stream_recoveries=controls['stream_recoveries'], completed_stream_recoveries=controls['stream_recoveries'],
                        planned_fork_evictions=controls['fork_evictions'], completed_fork_evictions=controls['fork_evictions'],
                        planned_host_profiles=2, completed_host_profiles=2, host_profiles=[
                            dict(passed=True, false_success_control=True, parameters_sha256='a'*64, **controls, **outcomes,observed_references=[dict(row) for row in observed],
                                 completed_sessions=sessions-1, completed_exchanges=exchanges-1),
                            dict(passed=True, false_success_control=True, parameters_sha256='b'*64,
                                 local_missing_evidence=0, stream_recoveries=0, fork_evictions=0,
                                 accepted_imports=0,refused_imports=0,observed_references=[],
                                 completed_sessions=1, completed_exchanges=1)]))

    def test_fuzz_inventory_has_one_owner(self):
        """Full CI executes each fuzz corpus once and leaves long socket/minifuzz work to Fuzz / JAM."""
        import ast
        import inspect
        import jam_fuzz_corpora
        from corpus_catalog import CORPUS_NAMES
        from e2e_checks import PLAN
        from jam_fuzz_checks import application_fuzzer_interface, application_minifuzz_interface
        fuzz = set(interface.CASES)
        self.assertTrue(fuzz)
        self.assertFalse(fuzz & set(CORPUS_NAMES))
        declared = {node.name for node in ast.parse(inspect.getsource(jam_fuzz_corpora)).body
                    if isinstance(node, ast.FunctionDef) and node.name.startswith('jam_fuzzer_')
                    and node.name.endswith('_corpus')}
        self.assertEqual(fuzz, declared)
        for check in (application_fuzzer_interface, application_minifuzz_interface):
            self.assertNotIn(check.__name__, PLAN.names('workload'))
        for setup in ('prepare_fuzzer_policy', 'prepare_minifuzz'):
            self.assertNotIn(setup, PLAN.names('setup'))

    def test_dedicated_runner_executes_complete_plan_once(self):
        """Every private shard runs exactly its complete plan; unsharded local execution still owns all work."""
        from contextlib import ExitStack
        from unittest.mock import Mock
        import jam_fuzz_checks
        for shard in (None, (1, 3), (2, 3), (3, 3)):
            complete = self.complete()
            selected, integration = interface.partition(shard, 'seed')
            tasks = {name: Mock(return_value=complete['cases'][name]) for name in interface.CASES}
            with self.subTest(shard=shard), tempfile.TemporaryDirectory() as folder, ExitStack() as stack:
                root = Path(folder)
                stack.enter_context(patch.dict(os.environ, JAM_FUZZ_SHARD='' if shard is None else f'{shard[0]}/3', CI_SHARD_SEED='seed'))
                stack.enter_context(patch.object(interface, 'BUILD', root))
                stack.enter_context(patch.object(interface, 'installed', return_value=(root/'compiler', None)))
                stack.enter_context(patch.object(interface, 'runtime_sources', return_value=[]))
                stack.enter_context(patch.object(interface, 'NativeChecks')).return_value.command.return_value = dict(output='fixture', exit_code=0)
                stack.enter_context(patch('nimony_crypto.prepare', return_value=(root/'crypto', None, {})))
                stack.enter_context(patch('bandersnatch_native.prepare', return_value=(root/'bs', None, {})))
                stack.enter_context(patch('nimony_quic.prepare', return_value=(root/'quic', root/'certs', {})))
                stack.enter_context(patch.dict(CORPORA.tasks, tasks, clear=True))
                setups = [stack.enter_context(patch.object(jam_fuzz_checks, name))
                          for name in ('prepare_peer', 'prepare_fuzzer_policy', 'prepare_minifuzz')]
                socket = stack.enter_context(patch.object(jam_fuzz_checks, 'application_fuzzer_interface', return_value=complete['socket']))
                minifuzz = stack.enter_context(patch.object(jam_fuzz_checks, 'application_minifuzz_interface', return_value=complete['minifuzz']))
                self.assertEqual(interface.main(), 0)
                workspace = root if shard is None else root/f'{shard[0]}-of-3'
                report = json.loads((workspace/'results.json').read_text())
                self.assertTrue(interface.passed(report))
                self.assertEqual(set(report['cases']), set(selected))
                self.assertEqual(report.get('jam_fuzz_shard'), None if shard is None else list(shard))
                self.assertEqual('socket' in report, integration)
                self.assertEqual('minifuzz' in report, integration)
            for name, operation in tasks.items():
                self.assertEqual(operation.call_count, int(name in selected))
            for operation in (*setups, socket, minifuzz):
                self.assertEqual(operation.call_count, int(integration))

    def test_randomized_shards_and_exact_verdicts(self):
        """All corpora have one reproducible owner; partial or foreign evidence cannot satisfy another scope."""
        import copy
        import random
        state = random.getstate()
        for seed in ('seed', 'other'):
            plans = [interface.partition((index, 3), seed) for index in (1, 2, 3)]
            self.assertEqual(plans, [interface.partition((index, 3), seed) for index in (1, 2, 3)])
            self.assertFalse(set(plans[0][0]) & set(plans[1][0]))
            self.assertEqual(set(plans[0][0]) | set(plans[1][0]), set(interface.CASES))
            self.assertEqual(plans[2], ((), True))
            for index, (names, integration) in enumerate(plans, 1):
                report = self.complete()
                report.update(jam_fuzz_shard=[index, 3], shard_seed=seed)
                report['cases'] = {name: report['cases'][name] for name in names}
                if not integration:
                    del report['socket'], report['minifuzz']
                self.assertTrue(interface.passed(report))
                self.assertIn(f'shard {index}/3', interface.summary(report))
                for name in names:
                    missing = copy.deepcopy(report)
                    del missing['cases'][name]
                    self.assertFalse(interface.passed(missing))
                changed = dict(report, jam_fuzz_shard=[index%3+1, 3])
                self.assertFalse(interface.passed(changed))
                if not integration:
                    sibling = next(name for name in interface.CASES if name not in names)
                    extra = copy.deepcopy(report)
                    extra['cases'][sibling] = self.complete()['cases'][sibling]
                    self.assertFalse(interface.passed(extra))
                    self.assertFalse(interface.passed(dict(report, socket={})))
                else:
                    missing = dict(report)
                    del missing['minifuzz']
                    self.assertFalse(interface.passed(missing))
        self.assertEqual(random.getstate(), state)
        self.assertNotEqual(interface.partition((1, 3), 'seed'), interface.partition((1, 3), 'other'))
        for value in ('0/3', '4/3', '1/2', '1/4', '1', 'x/3'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                interface.parse_shard(value)
        for seed in ('', ' ', 1):
            with self.assertRaises(ValueError):
                interface.partition((3, 3), seed)

    def test_invalid_shard_refuses_before_setup(self):
        """Bad selectors and seeds cannot prepare native dependencies or publish a successful partial result."""
        for shard, seed in (('1/2', 'seed'), ('0/3', 'seed'), ('1/3', ' ')):
            with self.subTest(shard=shard, seed=seed), patch.dict(os.environ,
                    JAM_FUZZ_SHARD=shard, CI_SHARD_SEED=seed), patch.object(interface, 'installed') as setup:
                with self.assertRaises(ValueError):
                    interface.main()
                setup.assert_not_called()

    def test_ci_summary_reads_its_private_shard(self):
        """Execute the workflow's real summary shell so a sibling report cannot supply the displayed coverage."""
        import subprocess
        text = (interface.ROOT/'.github/workflows/ci.yml').read_text()
        job = job_section(text, 'pvm-fuzz')
        script = next(command for command in commands(job) if 'JAM_FUZZ_SHARD' in command and 'GITHUB_STEP_SUMMARY' in command)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root/'summary.md'
            for index in (1, 2, 3):
                report = root/f'build/tests/jam-fuzzer-interface/{index}-of-3/summary.md'
                report.parent.mkdir(parents=True)
                report.write_text(f'private scope {index}\n')
            for index in (1, 2, 3):
                output.write_text('')
                subprocess.run(['bash', '-e', '-c', script], cwd=root, check=True, timeout=10,
                               env=dict(os.environ, JAM_FUZZ_SHARD=f'{index}/3', GITHUB_STEP_SUMMARY=str(output)))
                self.assertEqual(output.read_text(), f'private scope {index}\n')

    def test_every_declared_child_is_required(self):
        """No missing, extra or failed case can hide behind another successful child."""
        self.assertEqual(interface.CASES, tuple(sorted(CORPORA.tasks)))
        self.assertTrue(interface.CASES)
        self.assertTrue(interface.passed(self.complete()))
        for name in interface.CASES:
            report = self.complete()
            del report['cases'][name]
            self.assertFalse(interface.passed(report))
            report = self.complete()
            report['cases'][name]['passed'] = False
            self.assertFalse(interface.passed(report))
        report = self.complete()
        report['cases']['undeclared'] = dict(passed=True)
        self.assertFalse(interface.passed(report))
        report = self.complete()
        del report['socket']
        self.assertFalse(interface.passed(report))

    def test_transcript_and_native_stages_are_required(self):
        """A stale success flag cannot cover mismatched expected bytes, failed linking or failed native execution."""
        name = interface.CASES[0]
        for field, value in (('actual_sha256', 'b'*64), ('expected_sha256', ''),
                             ('build', dict(exit_code=1)), ('run', dict(exit_code=2)),
                             ('run', dict(exit_code=False)), ('run', None)):
            report = self.complete()
            report['cases'][name][field] = value
            self.assertFalse(interface.passed(report))
        report = self.complete()
        del report['cases'][name]['actual_sha256']
        self.assertFalse(interface.passed(report))

    def test_incomplete_guest_socket_work_is_required(self):
        """Partial loops, absent guest evidence and missing full-map/sibling checks fail the same aggregate gate."""
        for field in ('completed_sessions', 'completed_imports', 'retained_siblings',
                      'complete_state_queries', 'consensus_rejections', 'isolated_reconnects'):
            report = self.complete()
            report['socket']['guests'][field] -= 1
            self.assertFalse(interface.passed(report))
        report = self.complete()
        del report['socket']['guests']
        self.assertFalse(interface.passed(report))
        self.assertIn('guest socket evidence: failed or missing', interface.summary(report))

    def test_upstream_replay_cannot_be_skipped(self):
        """A zero upstream exit or outer success flag cannot replace all observed exchanges and the mismatch control."""
        report = self.complete()
        del report['minifuzz']
        self.assertFalse(interface.passed(report))
        for field, value in (('completed_sessions', 1), ('completed_exchanges', 8),
                             ('false_success_control', False), ('signed_imports', 0)):
            report = self.complete()
            report['minifuzz'][field] = value
            self.assertFalse(interface.passed(report))

    def test_observed_refusals_are_required_per_reference_and_profile(self):
        """Balanced total imports cannot hide absent, substituted or internally consistent partial refusal observations."""
        import copy
        good = self.complete()['minifuzz']
        self.assertGreater(good['completed_refused_imports'],0)
        for mutation in ('missing','balanced','boolean','reference','profile','duplicate','consistent-partial'):
            row = copy.deepcopy(good)
            selected = next(value for value in row['observed_references'] if value['refused_imports'])
            if mutation == 'missing': del row['completed_refused_imports']
            elif mutation == 'balanced':
                row['completed_refused_imports'] -= 1;row['completed_accepted_imports'] += 1
            elif mutation == 'boolean': row['host_profiles'][1]['refused_imports'] = False
            elif mutation == 'reference': selected['refused_imports'] -= 1;selected['accepted_imports'] += 1
            elif mutation == 'profile': row['host_profiles'][0]['refused_imports'] -= 1
            elif mutation == 'duplicate': row['host_profiles'][0]['observed_references'].append(copy.deepcopy(selected))
            else:
                # Adjust every claimed observation and total consistently; frozen source metadata still requires the missing refusal.
                for prefix in ('planned_','completed_'): row[prefix+'refused_imports'] -= 1
                row['signed_imports'] -= 1;row['host_profiles'][0]['refused_imports'] -= 1
                selected['refused_imports'] -= 1
                profile = next(value for value in row['host_profiles'][0]['observed_references'] if value['reference'] == selected['reference'])
                profile['refused_imports'] -= 1
                proof = next(value for value in row['independent_references'] if value['reference'] == selected['reference'])
                proof['refused_imports'] -= 1;proof['signed_imports'] -= 1
            self.assertFalse(interface.minifuzz_verified(row),mutation)
        self.assertIn('Observed accepted / refused imports:',interface.summary(self.complete()))

    def test_failed_setup_replaces_old_success(self):
        """An interrupted prerequisite writes a fresh failed report and explicit pending-engine summary."""
        with tempfile.TemporaryDirectory() as folder:
            build = Path(folder)
            (build/'results.json').write_text(json.dumps(self.complete()))
            with patch.object(interface, 'BUILD', build), patch.object(interface, 'installed', side_effect=OSError('fixture prerequisite failure')), patch.object(interface, 'announce'):
                self.assertEqual(interface.main(), 1)
            report = json.loads((build/'results.json').read_text())
            self.assertEqual(report['status'], 'failed')
            self.assertFalse(interface.passed(report))
            self.assertEqual(report['engine_validation'], 'pending')
            self.assertIn('pending compatible polkajam-fuzz engine', (build/'summary.md').read_text())

    def test_matrix_keeps_campaign_and_interface_distinct(self):
        """PVM-only dispatch excludes the interface; both opt-in families keep their own commands and artifacts."""
        text = (interface.ROOT/'.github/workflows/ci.yml').read_text()
        job = job_section(text, 'pvm-fuzz')
        from collections import Counter
        from workflow_fixtures import selected_families, event_context, family_section
        families = selected_families(text, 'pvm-fuzz', event_context())
        scopes = [interface.parse_shard(row['shard']) for row in families if row['group'] == 'jam-interface']
        plans = [interface.partition(scope, 'audit') for scope in scopes]
        self.assertEqual(Counter(name for names, _ in plans for name in names), Counter(interface.CASES))
        self.assertEqual(sum(integration for _, integration in plans), 1)
        focused = event_context('workflow_dispatch', suite='fuzz-pvm')
        self.assertEqual({row['group'] for row in selected_families(text, 'pvm-fuzz', focused)}, {'pvm'})
        section = family_section(text, 'pvm-fuzz', 'pvm', context=focused)
        self.assertIn('make fuzz-pvm-upstream', commands(section))
        self.assertNotIn('make check-jam-fuzzer-interface', commands(section))
        self.assertIn('build/tests/jam-fuzzer-interface/**/results.json', artifact_paths(job))

    def test_minifuzz_profile_completeness(self):
        """A dropped, duplicated, partial or unverified target profile cannot pass aggregate CI evidence."""
        import copy
        good = self.complete()['minifuzz']
        self.assertTrue(interface.minifuzz_verified(good))
        for mutation in ('missing', 'duplicate', 'control', 'partial', 'count'):
            row = copy.deepcopy(good)
            if mutation == 'missing': row['host_profiles'].pop()
            elif mutation == 'duplicate': row['host_profiles'][1]['parameters_sha256'] = 'a'*64
            elif mutation == 'control': row['host_profiles'][0]['false_success_control'] = False
            elif mutation == 'partial': row['host_profiles'][0]['completed_exchanges'] -= 1
            else: row['completed_host_profiles'] -= 1
            self.assertFalse(interface.minifuzz_verified(row))

    def test_local_missing_evidence_completeness(self):
        """Missing, partial, negative or substituted local-refusal counts cannot satisfy the declared process plan."""
        import copy
        good = self.complete()['minifuzz']
        for mutation in ('missing', 'partial', 'negative', 'substituted', 'invalid-profile'):
            row = copy.deepcopy(good)
            if mutation == 'missing': del row['completed_local_missing_evidence']
            elif mutation == 'partial': row['completed_local_missing_evidence'] = 0
            elif mutation == 'negative': row['planned_local_missing_evidence'] = -1
            elif mutation == 'substituted': row['host_profiles'][0]['local_missing_evidence'] = 0
            else: row['host_profiles'][0] = None
            self.assertFalse(interface.minifuzz_verified(row))
        # Profiles with no declared local-evidence cases still require explicit matching zero observations.
        good['planned_local_missing_evidence'] = good['completed_local_missing_evidence'] = 0
        good['host_profiles'][0]['local_missing_evidence'] = 0
        self.assertFalse(interface.minifuzz_verified(good)) # The source-owned full plan still requires its local control.

    def test_stream_recovery_completeness(self):
        """A skipped or substituted stream recovery cannot be hidden by complete upstream replay counts."""
        import copy
        for mutation in ('missing','partial','negative','substituted'):
            row = copy.deepcopy(self.complete()['minifuzz'])
            if mutation == 'missing': del row['completed_stream_recoveries']
            elif mutation == 'partial': row['completed_stream_recoveries'] -= 1
            elif mutation == 'negative': row['planned_stream_recoveries'] = -1
            else: row['host_profiles'][0]['stream_recoveries'] -= 1
            self.assertFalse(interface.minifuzz_verified(row))

    def test_fork_retention_completeness(self):
        """Eviction and retirement cannot disappear while upstream replay and all other controls remain complete."""
        import copy
        for mutation in ('missing','partial','negative','substituted'):
            row = copy.deepcopy(self.complete()['minifuzz'])
            if mutation == 'missing': del row['completed_fork_evictions']
            elif mutation == 'partial': row['completed_fork_evictions'] -= 1
            elif mutation == 'negative': row['planned_fork_evictions'] = -1
            else: row['host_profiles'][0]['fork_evictions'] -= 1
            self.assertFalse(interface.minifuzz_verified(row))

    def test_reference_family_and_fixture_completeness(self):
        """Missing or substituted whole-map families and internally consistent partial reports cannot pass CI."""
        import copy
        good = self.complete()['minifuzz']
        for mutation in ('missing','duplicate','extra','fixture','stream','sessions','imports','consistent-partial'):
            row = copy.deepcopy(good);reference = row['independent_references'][1]
            if mutation == 'missing': row['independent_references'].pop()
            elif mutation == 'duplicate': reference['reference'] = row['independent_references'][0]['reference']
            elif mutation == 'extra': reference['reference'] = 'undeclared_reference'
            elif mutation == 'fixture': reference['fixture_sha256'] = '0'*64
            elif mutation == 'stream': reference['expected_sha256'] = '0'*64
            elif mutation == 'sessions': reference['sessions'] -= 1
            elif mutation == 'imports': reference['signed_imports'] -= 1
            else:
                # All observed totals still agree with each other, but disagree with the independent fixture budget.
                row['planned_sessions'] -= 1;row['completed_sessions'] -= 1
                row['host_profiles'][0]['completed_sessions'] -= 1
            self.assertFalse(interface.minifuzz_verified(row),mutation)
