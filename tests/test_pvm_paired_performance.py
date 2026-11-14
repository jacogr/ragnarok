# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Check direct paired arithmetic, fresh failure evidence and detached baseline cleanup."""
import json
from copy import deepcopy
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import pvm_ci_performance as performance
from pvm_performance_fixtures import invocation_observations


def cells():
    """Independent timings distinguish median pair ratios from a ratio of pooled medians."""
    template = next(row['parsed'] for row in invocation_observations()['runs']
                    if row['case_id'] == 'pinky-1' and row['role'] == 'jit')
    rows = []
    for pair, base, candidate in [(0, 100, 60), (1, 300, 150)]:
        for version, value in [('baseline', base), ('candidate', candidate)]:
            samples = [dict(sample=i, cpu_ns=(1000 if version == 'baseline' else 2000)
                if i == 0 else 9999999 if i < 3 else value, wall_ns=value*2)
                for i in range(13)]
            parsed = deepcopy(template)
            parsed['invocation']['samples'] = samples
            rows.append(dict(case_id='pinky-1', pair=pair, version=version, parsed=parsed))
    return rows


def context(folder):
    """Describe passed current evidence without invoking a compiler or guest."""
    return SimpleNamespace(folder=folder, scope='all', expected_revision='a'*40, seals={},
        images={'guest': Path('candidate')}, control_sequence=0, checks=object(), report=dict(status='passed',
        revision='a'*40, architecture='arm64', identity={}))


class PairedPerformanceTests(unittest.TestCase):
    """Exercise evidence acceptance rather than source spelling or internal helper sequences."""

    def test_direct_pair_ratios_and_warmup_exclusion(self):
        """Warmup outliers cannot affect reused cells; every version is paired before aggregation."""
        rows = performance.paired_summary(cells(), [dict(case_id='pinky-1')], 2)
        cpu = next(row for row in rows if row['phase'] == 'reuse' and row['clock'] == 'cpu_ns')
        self.assertAlmostEqual(cpu['ratio'], .55)
        self.assertEqual(cpu['baseline_ns'], 200)
        self.assertEqual(cpu['candidate_ns'], 105)
        self.assertEqual(cpu['range'], [.5, .6])
        cold = next(row for row in rows if row['phase'] == 'cold' and row['clock'] == 'cpu_ns')
        self.assertEqual(cold['ratio'], 2)

    def test_missing_duplicate_unordered_or_invalid_cells_refuse(self):
        """Incomplete or malformed evidence never produces a plausible partial timing table."""
        for kind in ['missing', 'duplicate', 'unordered', 'negative', 'bool', 'boundary', 'policy']:
            with self.subTest(kind=kind):
                rows = cells()
                if kind == 'missing': rows.pop()
                elif kind == 'duplicate': rows.append(rows[0])
                elif kind == 'unordered': rows[0]['parsed']['invocation']['samples'][0]['sample'] = 1
                elif kind == 'negative': rows[0]['parsed']['invocation']['samples'][4]['cpu_ns'] = -1
                elif kind == 'bool': rows[0]['parsed']['invocation']['samples'][4]['cpu_ns'] = True
                elif kind == 'boundary': rows[0]['parsed']['invocation']['measurement'] = {}
                else: rows[0]['parsed']['policy']['jit_built'] = False
                with self.assertRaises(ValueError):
                    performance.paired_summary(rows, [dict(case_id='pinky-1')], 2)

    def test_zero_resolution_is_explicit(self):
        """A zero denominator yields no ratio rather than infinity or a fabricated speedup."""
        rows = cells()
        for sample in rows[0]['parsed']['invocation']['samples']: sample['cpu_ns'] = 0
        observed = performance.paired_summary(rows, [dict(case_id='pinky-1')], 2)
        self.assertIsNone(next(row for row in observed if row['phase'] == 'reuse'
                               and row['clock'] == 'cpu_ns')['ratio'])

    def test_bad_request_replaces_stale_pair_success_only(self):
        """Reject a branch-name baseline, erase stale paired success and preserve canonical evidence."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            canonical = folder/'results.json'
            canonical.write_text('canonical evidence')
            (folder/'paired-results.json').write_text('{"status":"passed"}')
            (folder/'paired-summary.md').write_text('old accepted ratios')
            with self.assertRaises(ValueError):
                performance.PairedRunner(context(folder), 'master')
            self.assertEqual(json.loads((folder/'paired-results.json').read_text())['status'], 'failed')
            self.assertNotIn('old accepted', (folder/'paired-summary.md').read_text())
            self.assertEqual(canonical.read_text(), 'canonical evidence')

    def test_canonical_failure_invalidates_an_earlier_paired_success(self):
        """Failed current qualification cannot leave a previous same-runner result looking current."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder/'paired-results.json').write_text('{"status":"passed"}')
            (folder/'paired-summary.md').write_text('old accepted ratios')
            with (patch.object(performance, 'BUILD', folder),
                  patch.object(sys, 'argv', ['pvm_ci_performance.py', '--baseline', 'b'*40]),
                  patch.object(performance.PerformanceRunner, 'execute', side_effect=RuntimeError('qualification')),
                  self.assertRaisesRegex(RuntimeError, 'qualification')):
                performance.main()
            self.assertEqual(json.loads((folder/'paired-results.json').read_text())['status'], 'incomplete')
            self.assertNotIn('old accepted', (folder/'paired-summary.md').read_text())

    def test_unpaired_request_retires_previous_paired_artifacts(self):
        """A later unpaired run cannot expose an old accepted paired cohort, even if qualification fails."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            for name in ('paired-results.json', 'paired-summary.md'):
                (folder/name).write_text('old paired success')
            with (patch.object(performance, 'BUILD', folder),
                  patch.object(sys, 'argv', ['pvm_ci_performance.py', '--baseline', '']),
                  patch.object(performance.PerformanceRunner, 'execute', side_effect=RuntimeError('qualification')),
                  self.assertRaisesRegex(RuntimeError, 'qualification')):
                performance.main()
            self.assertFalse((folder/'paired-results.json').exists())
            self.assertFalse((folder/'paired-summary.md').exists())

    def test_cleanup_is_required_before_accepting_paired_results(self):
        """Cleanup success permits publication; a raised interruption or failed exit erases accepted artifacts."""
        for failure in ('success', 'interrupt', 'os-error', 'exit', 'primary-and-cleanup'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary)
                current = context(folder)
                current.cases = [dict(case_id='pinky-1')]
                class Collected(performance.PairedRunner):
                    """Supply a complete literal cohort while exercising real acceptance and cleanup ordering."""
                    def collect(self):
                        """No native execution is claimed; only the source owner's cleanup remains pending."""
                        self.created = True
                        self.report['runs'] = cells()
                        self.report['summary'] = performance.paired_summary(cells(), current.cases, 2)
                        if failure == 'primary-and-cleanup':
                            raise RuntimeError('primary process failure')
                def remove(*args, **kwargs):
                    """Observe acceptance state at cleanup, then return or raise the selected outcome."""
                    self.assertNotEqual(json.loads((folder/'paired-results.json').read_text())['status'], 'passed')
                    self.assertNotIn('| Case |', (folder/'paired-summary.md').read_text())
                    if failure == 'interrupt': raise KeyboardInterrupt()
                    if failure == 'os-error': raise OSError('cleanup launch failure')
                    return subprocess.CompletedProcess(args[0], 0 if failure == 'success' else 1, '', 'cleanup')
                runner = Collected(current, 'b'*40)
                with patch.object(performance.subprocess, 'run', side_effect=remove):
                    if failure == 'success':
                        self.assertEqual(runner.execute()['status'], 'passed')
                    else:
                        error = KeyboardInterrupt if failure == 'interrupt' else OSError if failure == 'os-error' else RuntimeError
                        with self.assertRaises(error): runner.execute()
                observed = json.loads((folder/'paired-results.json').read_text())
                if failure == 'success':
                    self.assertIn('| Case |', (folder/'paired-summary.md').read_text())
                else:
                    self.assertEqual(observed['status'], 'failed')
                    self.assertIn('cleanup_error', observed)
                    self.assertNotIn('| Case |', (folder/'paired-summary.md').read_text())
                    if failure == 'primary-and-cleanup':
                        self.assertEqual(observed['error'], 'primary process failure')

    def test_complete_alternating_cohort_and_interrupted_recheck(self):
        """Publish every paired full-call cell, then invalidate that success on a failed new run."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            current = context(folder)
            current.cases = [dict(case_id='pinky-1', family='guest', case='pinky', limit=1)]
            templates = {row['version']: row['parsed'] for row in cells() if row['pair'] == 0}
            class Controlled(performance.PairedRunner):
                """Supply literal parsed clocks while exercising the real scheduling/publication loop."""
                fail_at = 0
                launched = 0
                def comparison_images(self):
                    """No compiler or native execution is claimed by this orchestration fixture."""
                    return {'guest': Path('baseline')}, {'guest': Path('candidate')}
                def controls(self, case, role):
                    """Record which executable received the baseline controls."""
                    self.report['controls'].append(dict(version=self.images['guest'].name))
                def invocation(self, case, role):
                    """Both versions receive the same fixture marker and differ only in executable."""
                    return [self.images['guest'].name], {'input': 'same'}, None
                def command(self, arguments, name, env=None, **options):
                    """Retain observable inputs, or fail before accepting the configured process."""
                    self.launched += 1
                    if self.fail_at and self.launched == self.fail_at:
                        raise RuntimeError('injected process failure')
                    return dict(command=arguments, output=arguments[0], log=name, exit_code=0,
                                benchmark_environment=env)
                def parse(self, output, case, role):
                    """Literal full-invocation fixtures retain the canonical measurement/policy shape."""
                    return {'pinky-1': deepcopy(templates[output])}
            runner = Controlled(current, 'b'*40)
            observed = runner.execute()
            self.assertEqual(observed['status'], 'passed')
            self.assertEqual(len(observed['runs']), 22)
            self.assertEqual(observed['controls'], [dict(version='baseline'), dict(version='candidate')])
            for pair in range(11):
                rows = [row for row in observed['runs'] if row['pair'] == pair]
                self.assertEqual([row['version'] for row in rows], rows[0]['order'])
                self.assertEqual({row['version'] for row in rows}, {'baseline', 'candidate'})
                self.assertTrue(all(row['run']['benchmark_environment']['input'] == 'same' for row in rows))
            orders = [tuple(row['order']) for row in observed['runs'][::2]]
            self.assertEqual(set(orders), {('baseline', 'candidate'), ('candidate', 'baseline')})
            self.assertLessEqual(abs(orders.count(orders[0])-orders.count(orders[1])), 1)
            failed = Controlled(current, 'b'*40)
            failed.fail_at = 3
            with self.assertRaisesRegex(RuntimeError, 'injected process'):
                failed.execute()
            self.assertEqual(json.loads((folder/'paired-results.json').read_text())['status'], 'failed')
            self.assertNotIn('| Case |', (folder/'paired-summary.md').read_text())

    def test_both_revisions_build_at_one_path_with_equal_profiles(self):
        """Real detached checkouts feed different source bytes to the same driver path and build flags."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def git(*args):
                """Keep this source-switching fixture isolated from the application repository."""
                return subprocess.run(['git', *args], cwd=root, check=True,
                                      capture_output=True, text=True).stdout.strip()
            git('init', '-q')
            (root/'spec').mkdir()
            for name in ['toolchain.json', 'polkavm-pins.json', 'pins.json']:
                (root/'spec'/name).write_text('{"pin":1}')
            driver = root/'tests/performance/pvm_sieve.nim'
            driver.parent.mkdir(parents=True)
            driver.write_text('unchanged driver')
            source = root/'src/version.nim'
            source.parent.mkdir()
            source.write_text('baseline source')
            git('add', '.')
            commit = ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                      '-c', 'commit.gpgsign=false', 'commit', '-qam']
            git(*commit, 'baseline')
            baseline = git('rev-parse', 'HEAD')
            source.write_text('candidate source')
            git(*commit, 'candidate')
            candidate = git('rev-parse', 'HEAD')
            git('remote', 'add', 'origin', str(root))
            folder = root/'build'
            folder.mkdir()
            seen = []
            class Builds:
                """Observe real source selection without claiming native compilation or performance."""
                def command(self, arguments, name, environment=None, timeout=180):
                    """Execute only Git fixture operations and retain their ordinary result shape."""
                    run = subprocess.run(arguments, cwd=root, capture_output=True, text=True, timeout=timeout)
                    return dict(command=arguments, log=name, exit_code=run.returncode,
                                output=run.stdout+run.stderr)
                def build(self, compiler, source, name, **profile):
                    """A fake executable records which actual checkout bytes and profile reached the builder."""
                    content = (source.parents[2]/'src/version.nim').read_text()
                    seen.append((source, content, profile['defines'], profile['cflags']))
                    binary = folder/name
                    binary.write_text(content)
                    return dict(command=[str(compiler), str(source)], log=name, exit_code=0, output=''), binary
            current = context(folder)
            current.report['revision'] = candidate
            current.cases = [dict(case_id='pinky-1', family='guest', case='pinky', limit=1)]
            current.checks = Builds()
            current.compiler = root/'compiler'
            current.defines = ['pvmArm64Jit']
            runner = performance.PairedRunner(current, baseline)
            try:
                with patch.object(performance, 'ROOT', root):
                    base_images, candidate_images = runner.comparison_images()
                self.assertEqual([row[1] for row in seen], ['baseline source', 'candidate source'])
                self.assertEqual(seen[0][0], seen[1][0])
                self.assertEqual(seen[0][2:], seen[1][2:])
                self.assertEqual(base_images['guest'].read_text(), 'baseline source')
                self.assertEqual(candidate_images['guest'].read_text(), 'candidate source')
                self.assertEqual(git('rev-parse', 'HEAD'), candidate)
                self.assertNotEqual(runner.report['source_manifests']['baseline'],
                                    runner.report['source_manifests']['candidate'])
            finally:
                if runner.source.exists(): git('worktree', 'remove', str(runner.source))
            driver.write_text('changed measuring driver')
            git(*commit, 'different driver')
            current.report['revision'] = git('rev-parse', 'HEAD')
            refused = performance.PairedRunner(current, baseline)
            try:
                with patch.object(performance, 'ROOT', root), self.assertRaisesRegex(ValueError, 'driver differs'):
                    refused.comparison_images()
            finally:
                if refused.source.exists(): git('worktree', 'remove', str(refused.source))

    def test_failed_baseline_build_releases_its_worktree(self):
        """A real detached checkout is removed after an injected compiler failure."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def git(*args):
                """Run only the isolated fixture repository's Git commands."""
                return subprocess.run(['git', *args], cwd=root, check=True,
                                      capture_output=True, text=True).stdout.strip()
            git('init', '-q')
            (root/'source').write_text('baseline')
            git('add', 'source')
            git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                'commit', '-qm', 'fixture')
            baseline = git('rev-parse', 'HEAD')
            folder = root/'build'
            folder.mkdir()
            class Failing(performance.PairedRunner):
                """Reach the cleanup boundary with a real worktree and an explicit compile refusal."""
                def comparison_images(self):
                    """Create the owned snapshot, then fail before any timing can be accepted."""
                    git('worktree', 'add', '--detach', str(self.source), baseline)
                    self.created = True
                    raise RuntimeError('injected baseline compile failure')
            runner = Failing(context(folder), baseline)
            with patch.object(performance, 'ROOT', root), self.assertRaisesRegex(RuntimeError, 'injected'):
                runner.execute()
            self.assertFalse(runner.source.exists())
            self.assertEqual(git('worktree', 'list', '--porcelain').count('worktree '), 1)
            self.assertEqual(json.loads((folder/'paired-results.json').read_text())['status'], 'failed')
            self.assertNotIn('| Case |', (folder/'paired-summary.md').read_text())


if __name__ == '__main__':
    unittest.main()
