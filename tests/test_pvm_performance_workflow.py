# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Exercise scheduled native comparisons, focused scopes and evidence without running benchmarks."""
from pathlib import Path, PurePosixPath
import os
import subprocess
import tempfile
import unittest
from harness_fixtures import make_plan
from workflow_fixtures import artifact_paths, commands, event_context, expression, family_section, selected_families, workflow

ROOT = Path(__file__).resolve().parents[1]


class PvmPerformanceWorkflowTests(unittest.TestCase):
    """One complete native path owns PVM samples; unrelated requests cannot start it."""

    def test_paired_baseline_reaches_each_selected_native_job(self):
        """An immutable manual baseline reaches both architectures without selecting a different cohort."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        context = event_context('workflow_dispatch', suite='bench-pvm')
        context['inputs'].update(pvm_architecture='all', pvm_baseline_revision='a'*40)
        families = selected_families(text, 'pvm-comparison', context)
        self.assertEqual({family['group'] for family in families}, {'arm64', 'x86_64'})
        for family in families:
            section = family_section(text, 'pvm-comparison', family['group'], context=context)
            request = dict(context, matrix=dict(family=family))
            self.assertEqual(expression(section['env']['PVM_BASELINE_REVISION'], request), 'a'*40)

    def test_unpaired_job_summary_cannot_display_a_stale_paired_table(self):
        """Execute the summary consumer with stale pair evidence and both requested pairing states."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = family_section(text, 'pvm-comparison', 'arm64',
                                 context=event_context('workflow_dispatch', suite='bench-pvm'))
        script = next(step['run'] for step in section['steps']
                      if 'paired-summary.md' in step.get('run', ''))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            folder = root/'build/tests/pvm-performance'
            folder.mkdir(parents=True)
            (folder/'summary.md').write_text('canonical evidence\n')
            (folder/'paired-summary.md').write_text('paired evidence\n')
            for baseline in ('', 'a'*40):
                target = root/'summary'
                target.unlink(missing_ok=True)
                env = dict(os.environ, GITHUB_STEP_SUMMARY=str(target), PVM_BASELINE_REVISION=baseline)
                subprocess.run(['bash', '-eu', '-c', script], env=env, cwd=root,
                               capture_output=True, text=True, check=True)
                self.assertIn('canonical evidence', target.read_text())
                self.assertEqual('paired evidence' in target.read_text(), bool(baseline))

    def test_regular_requests_compare_both_architectures_once(self):
        """Merge and full/performance requests schedule one qualified comparison on each real CPU."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        for context in (event_context(), event_context('workflow_dispatch', suite='full'),
                        event_context('workflow_dispatch', suite='perf'),
                        event_context('pull_request', 'labeled', 'ci:perf'),
                        event_context('pull_request', 'labeled', 'ci:full')):
            families = selected_families(text, 'pvm-comparison', context)
            self.assertEqual({f['group'] for f in families}, {'arm64', 'x86_64'})
            for family in families:
                section = family_section(text, 'pvm-comparison', family['group'], context=context)
                selected = commands(section)
                self.assertEqual(selected.count('make bench-pvm-performance'), 1)
                request = dict(context, matrix=dict(family=family))
                self.assertEqual(expression(section['env']['PVM_PERF_SCOPE'], request), 'all')
                self.assertEqual(expression(section['env']['PVM_CI_ARCH'], request), family['group'])
                self.assertEqual(expression(section['env']['PVM_CI_JOB_NAME'], request),
                                 expression(section['name'], request))
                self.assertEqual(expression(section['runs-on'], request), family['os'])
                self.assertIn('build/tests/pvm-performance/*.json', artifact_paths(section))
                self.assertIn('build/tests/pvm-performance/*.csv', artifact_paths(section))
            # The storage performance matrix must not retain an overlapping PVM benchmark path.
            for family in selected_families(text, 'perf', context):
                section = family_section(text, 'perf', family['group'], context=context)
                self.assertFalse(any('bench-pvm' in command for command in commands(section)))

    def test_focused_scopes_reuse_the_same_runner_and_can_select_one_cpu(self):
        """Manual full-PVM/DOOM scope changes arguments and native runner selection, not the pipeline."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        for suite, scope in [('bench-pvm', 'all'), ('bench-doom', 'doom')]:
            for arch in ('all', 'arm64', 'x86_64'):
                context = event_context('workflow_dispatch', suite=suite)
                context['inputs']['pvm_architecture'] = arch
                families = selected_families(text, 'pvm-comparison', context)
                self.assertEqual({f['group'] for f in families},
                                 {'arm64', 'x86_64'} if arch == 'all' else {arch})
                for family in families:
                    section = family_section(text, 'pvm-comparison', family['group'], context=context)
                    self.assertEqual(commands(section).count('make bench-pvm-performance'), 1)
                    request = dict(context, matrix=dict(family=family))
                    self.assertEqual(expression(section['env']['PVM_PERF_SCOPE'], request), scope)
                self.assertEqual(selected_families(text, 'perf', context), [])

    def test_lightweight_or_foreign_requests_do_not_collect_timings(self):
        """PR updates, unrelated labels and closed PRs preserve their narrow verification scope."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        for context in (event_context('pull_request', 'synchronize'),
                        event_context('pull_request', 'labeled', 'lgtm'),
                        event_context('pull_request', 'labeled', 'ci:unit'),
                        event_context('pull_request', 'labeled', 'ci:perf', state='closed'),
                        event_context('workflow_dispatch', suite='tooling')):
            self.assertEqual(selected_families(text, 'pvm-comparison', context), [])

    def test_original_read_width_json_is_retained_without_native_build_payloads(self):
        """Ordinary native routes retain either original width proof, including first failure evidence."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        contexts = (event_context(), event_context('workflow_dispatch', suite='full'),
                    event_context('workflow_dispatch', suite='perf'),
                    event_context('workflow_dispatch', suite='bench-pvm'),
                    event_context('workflow_dispatch', suite='bench-doom'),
                    event_context('pull_request', 'labeled', 'ci:perf'),
                    event_context('pull_request', 'labeled', 'ci:full'))
        for context in contexts:
            for family in selected_families(text, 'pvm-comparison', context):
                section = family_section(text, 'pvm-comparison', family['group'], context=context)
                paths = artifact_paths(section)
                for name in ('arm-evidence/pvm_read_widths_arm64.json',
                             'x86-evidence/pvm_read_widths_x86_64.json'):
                    proof = 'build/tests/pvm-native/pvm_shared_read_widths_'+name
                    self.assertTrue(any(PurePosixPath(proof).match(pattern) for pattern in paths))
                for name in ('pvm_shared_read_widths_x86',
                             'pvm_shared_read_widths_x86-evidence/generated.c',
                             'pvm_shared_read_widths_arm-evidence/unrelated.json',
                             'unrelated-evidence/pvm_read_widths_arm64.json'):
                    private = 'build/tests/pvm-native/'+name
                    self.assertFalse(any(PurePosixPath(private).match(pattern) for pattern in paths))
                upload, = [step for step in section['steps']
                           if str(step.get('with', {}).get('name', '')).startswith('pvm-performance-')]
                self.assertTrue(expression(upload['if'], dict(context, cancelled=True)))

    def test_native_preflight_fetches_locked_crypto_before_offline_state_checks(self):
        """Standalone native qualification owns the new product fixture's locked offline closure."""
        planned = make_plan('check-pvm-native',
            skip=('toolchain', 'sources', 'rust-tools', 'check-inventory'))
        fetch = 'cargo fetch --locked --manifest-path native/bandersnatch/Cargo.toml'
        self.assertIn(fetch, planned)
        self.assertLess(planned.index(fetch), planned.index('tools/pvm_native_ci.py'))

    def test_make_qualifies_before_samples_and_latest_does_not_build(self):
        """Standalone execution owns setup/qualification; downloading evidence starts no guest toolchain."""
        planned = make_plan('bench-pvm-performance', skip=('toolchain', 'sources', 'rust-tools', 'check-inventory'))
        self.assertLess(planned.index('tools/pvm_native_ci.py'), planned.index('tools/pvm_ci_performance.py'))
        self.assertIn('cargo fetch --locked', planned)
        latest = make_plan('pvm-perf-latest')
        self.assertIn('tools/pvm_performance_latest.py', latest)
        self.assertNotIn('cargo ', latest)
        self.assertNotIn('tools/pvm_native_ci.py', latest)


if __name__ == '__main__':
    unittest.main()
