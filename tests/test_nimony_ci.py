# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""CI safeguards for trusted archives, complete source inventories and honest partial-coverage reporting.

Exposes NimonyCISafeguards for unittest discovery; test methods exercise the stated contracts.
"""
import io
import re
import hashlib
import json
from pathlib import Path
import sys
import subprocess
import tarfile
import unittest
from harness_fixtures import temporary_folder
import threading
from unittest.mock import patch
from workflow_fixtures import event_context, expression, job_section, selected_families, family_section, job_condition

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from toolchain_archives import download, extract
from setup_nimony import verify_identity, verify_version, host_pins, install, installed, cache_directory
from summarize_tests import summarize
import test_modules as modules
import build_bandersnatch as bandersnatch


# Build tiny inert tar fixtures; no test executes a downloaded or fabricated compiler.
def archive(name, data=b'fixture'):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode='w') as tar:
        member = tarfile.TarInfo(name)
        member.size = len(data)
        tar.addfile(member, io.BytesIO(data))
    return output.getvalue()


# Supply fresh empty groups so summary scenarios can test scope without borrowing other jobs' evidence.
def network_report(**workloads):
    return dict(status='blocked', suites=[], runtime=[], privacy=[], nominal=[], schemas=[], **workloads)


# Rejection paths prevent archive substitution, source omissions and misleading green migration summaries.
class NimonyCISafeguards(unittest.TestCase):
    # Merging the compiler migration must not leave duplicate CI workflows or branch-specific skipped gates.
    def test_single_canonical_ci_workflow(self):
        folder = ROOT/'.github/workflows'
        names = sorted(path.name for path in folder.iterdir() if path.suffix in ('.yml', '.yaml'))
        self.assertEqual(names, ['ci.yml'])
        text = (folder/'ci.yml').read_text()
        self.assertNotIn('github.head_ref', text)
        self.assertNotIn('github.ref_name', text)
        # PR updates request only smoke; heavy jobs still require explicit labels.
        triggers = text.split('"on":\n', 1)[1].split('\npermissions:', 1)[0]
        self.assertIn('push:\n    branches: [master]\n', triggers)
        self.assertIn('pull_request:\n    types: [opened, reopened, synchronize, labeled]\n', triggers)
        self.assertIn('workflow_dispatch:\n    inputs:\n      suite:', triggers)
        self.assertIn('type: choice\n        options: [smoke, jit-x86, jit-x86-replay, jit-arm-profile, unit, e2e, build, docker, interop, perf, ref-pvm, fuzz, fuzz-pvm, bench-pvm, bench-doom, pvm-backends, bench-storage, bench-storage-growth, full]\n        default: full', triggers)
        self.assertNotIn('pull_request_target', triggers)
        for target in ('check-models', 'check-python', 'check-modules', 'check-unit', 'check-failures', 'check-guards', 'check-e2e',
                       'check-telemetry-interop-ci', 'check-pvm-reference'):
            # Every group runs once and independently; no omnibus duplicate or serial CI dependency chain.
            self.assertEqual(text.count('run: make '+target+'\n'), 1)
        self.assertNotIn('needs:', text)
        self.assertNotIn('run: make check\n', text)
        self.assertNotIn('mkdir', text)
        self.assertNotIn('nimony-trial', text)
        self.assertNotIn('tools/setup_nimony.py', text)
        self.assertNotIn('cargo fetch', text)

    def test_opt_in_x86_qualification_uses_one_native_comparison_job(self):
        """The experimental backend runs only by explicit CI dispatch, without activating ordinary ARM work."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        for suite in ('jit-x86', 'jit-x86-replay'):
            context = event_context('workflow_dispatch', suite=suite)
            self.assertTrue(expression(job_condition(text, 'pvm-comparison'), context))
            self.assertEqual(selected_families(text, 'pvm-comparison', context),
                [dict(name='Linux x86-64', group='x86_64', os='ubuntu-26.04')])
        self.assertEqual(len(selected_families(text, 'pvm-comparison', event_context())), 2)
        section = job_section(text, 'pvm-comparison')
        self.assertIn('run: make check-pvm-x86-jit', section)
        self.assertIn('build/tests/pvm-x86-jit/*.json', section)
        self.assertNotIn('continue-on-error', section)

    def test_manual_arm_profile_is_one_native_job(self):
        """ARM profiles keep calibration and native qualification without adding jobs to ordinary CI."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        context = event_context('workflow_dispatch', suite='jit-arm-profile')
        self.assertTrue(expression(job_condition(text, 'pvm-comparison'), context))
        self.assertEqual(selected_families(text, 'pvm-comparison', context),
                         [dict(name='Linux ARM64',group='arm64',os='ubuntu-26.04-arm')])
        section=job_section(text,'pvm-comparison')
        self.assertIn('run: make profile-pvm-arm64-linux',section)
        self.assertIn('build/tests/pvm-arm64-profiles/*',section)
        self.assertNotIn('continue-on-error',section)

    def test_pr_updates_request_only_smoke_with_isolated_concurrency(self):
        """An ordinary PR update runs the small gate without requesting or cancelling heavy CI."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = family_section(text, 'build', 'smoke')
        self.assertIn("github.event_name == 'pull_request' && github.event.pull_request.state == 'open' && github.event.action != 'labeled'", section)
        self.assertIn("github.event_name == 'push' ||", section)
        self.assertIn("inputs.suite == 'smoke'", section)
        self.assertIn('run: make check-smoke', section)
        self.assertIn('persist-credentials: false', section)
        self.assertNotIn('needs:', section)
        self.assertNotIn('pull_request_target', text)
        self.assertIn("format('smoke-{0}', github.event.pull_request.number)", text)
        self.assertNotIn('github.event.pull_request.labels', text)
        # These plans require no fixture checkout, Cargo dependency build or native linker provisioning.
        plan = subprocess.check_output(['make', '-n', '--no-print-directory', 'check-smoke'], cwd=ROOT, text=True)
        for unwanted in ('setup_submodules.py', 'setup_tlanif.py', 'build_crypto.py', 'apt-get', 'cargo fetch'):
            self.assertNotIn(unwanted, plan)
        self.assertIn('format.py --check', plan)
        self.assertIn('test_modules.py --compiler "$NIMONY" --smoke', plan)

    def test_lgtm_requests_only_smoke_without_cancelling_heavy_runs(self):
        """Review approval creates fresh Smoke evidence on the same head, isolated from heavy requests."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        event = event_context('pull_request', 'labeled', 'lgtm')
        self.assertEqual([row['name'] for row in selected_families(text, 'build', event)], ['Smoke'])
        jobs = re.findall(r'^  ([\w-]+):\n', text.split('jobs:\n', 1)[1], re.MULTILINE)
        for job in jobs:
            self.assertEqual(bool(expression(job_condition(text, job), event)), job == 'build')
        key = re.search(r'^  group: ci-\$\{\{ github.workflow \}\}-\$\{\{ (.*) \}\}$',
                        text, re.MULTILINE).group(1)
        keys = {}
        for label in ('lgtm', 'ci:full', 'unrelated'):
            request = event_context('pull_request', 'labeled', label)
            request['github'].update(run_id=100, ref='refs/pull/1791/merge')
            request['github']['event']['pull_request']['number'] = 1791
            keys[label] = expression(key, request)
        self.assertEqual(keys['lgtm'], 'smoke-1791')
        self.assertNotEqual(keys['lgtm'], keys['ci:full'])
        self.assertNotEqual(keys['lgtm'], keys['unrelated'])

    # Ordinary PR updates retain only the named lightweight workload.
    def test_smoke_build_scope(self):
        """A lightweight request expands only Smoke without an extra aggregate runner."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        families = selected_families(text, 'build', event_context('pull_request', 'synchronize'))
        self.assertEqual([row['group'] for row in families], ['smoke'])
        self.assertNotIn('minutes', families[0])

    def test_source_shares_linux_packaging_without_expanding_smoke(self):
        """Linux reuses packaging setup while Tooling owns independent compiler rejection checks."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        family = family_section(text, 'build', 'binary', 'Linux & Docker')
        commands = ['package-binary', 'check-modules', 'check-docker']
        positions = [family.index('run: make '+command+'\n') for command in commands]
        self.assertEqual(positions, sorted(positions))
        for target in ('check-modules',):
            # Explicit status conditions allow every independent check after an earlier failed step.
            step = next(s for s in re.findall(r'^      - .*?(?=^      - |\Z)', family, re.M | re.S)
                        if 'run: make '+target+'\n' in s)
            guard = re.search(r'        if: (.+)', step).group(1)
            context = dict(event_context(), matrix=dict(family=dict(group='binary', platform='linux-amd64')))
            self.assertIn('!cancelled()', guard)
            self.assertTrue(expression(guard, context))
            self.assertFalse(expression(guard, dict(context, cancelled=True)))
        for group in ('modules',):
            self.assertIn('build/tests/'+group+'/results.json', family)
            self.assertIn('run: make summary-'+group+' SUMMARY_OUTPUT=', family)
        # Unit requests preserve checks without adding binary archives or a Docker build.
        context = event_context('workflow_dispatch', suite='unit')
        checks = family_section(text, 'build', 'checks', context=context)
        self.assertIn('run: make check-modules', checks)
        self.assertNotIn('run: make check-guards', checks)
        self.assertNotIn('run: make check-guards', family)
        self.assertNotIn('run: make package-binary', checks)
        self.assertNotIn('run: make check-docker', checks)
        for group, name in [('smoke', None), ('binary', 'macOS')]:
            # The fast gate and macOS packaging gain no compiler-guard work.
            selected = family_section(text, 'build', group, name)
            self.assertNotIn('run: make check-modules', selected)
            self.assertNotIn('run: make check-guards', selected)

    def test_every_job_uses_shared_timeout(self):
        """Randomized workload variance has one 60-minute safety limit across all CI jobs."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        jobs = re.findall(r'^  ([\w-]+):\n', text.split('jobs:\n', 1)[1], re.MULTILINE)
        self.assertEqual(text.count('&ci-job-timeout 60'), 1)
        for job in jobs:
            # Every workload must opt into the same bound rather than inherit six hours.
            section = job_section(text, job)
            expected = '&ci-job-timeout 60' if job == 'build' else '*ci-job-timeout'
            self.assertIn('timeout-minutes: '+expected+'\n', section)
            self.assertEqual(section.count('    timeout-minutes:'), 1)
            self.assertNotIn('"minutes":', section)

    # Scope guards must act on the label addition, never on persistent PR labels or a branch name.
    def test_ci_request_scopes(self):
        """Full and focused requests retain exact coverage under the unified Build matrix."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        groups = {'build': ['smoke', 'python', 'binary', 'binary'],
                  'interop': ['pvm-reference', 'telemetry-interop'],
                  'perf': ['bench-pvm-all', 'bench-storage']}
        unit = ['smoke', 'python', 'checks']
        for event in (event_context(), event_context('workflow_dispatch', suite='full'),
                      event_context('pull_request', 'labeled', 'ci:full')):
            for job, wanted in groups.items():
                self.assertEqual([row['group'] for row in selected_families(text, job, event)], wanted)
        for action in ('opened', 'reopened', 'synchronize'):
            # Automatic updates cannot turn persistent heavy labels into heavy work.
            for job in groups:
                rows = selected_families(text, job, event_context('pull_request', action))
                self.assertEqual([row['group'] for row in rows], ['smoke'] if job == 'build' else [])
        labels = {'lgtm': {'build': ['smoke']}, 'ci:unit': {'build': unit}, 'ci:docker': {'build': ['docker']},
                  'ci:interop': {'interop': groups['interop']}, 'ci:perf': {'perf': groups['perf']}}
        for label in (*labels, 'ci:e2e', 'ci:fuzz', 'unrelated'):
            for job in groups:
                rows = selected_families(text, job, event_context('pull_request', 'labeled', label))
                self.assertEqual([row['group'] for row in rows], labels.get(label, {}).get(job, []))
        manual = {'smoke': ('build', ['smoke']), 'unit': ('build', unit),
                  'build': ('build', ['binary', 'binary']), 'docker': ('build', ['docker']),
                  'interop': ('interop', groups['interop']), 'ref-pvm': ('interop', ['pvm-reference']),
                  'perf': ('perf', groups['perf']), 'bench-pvm': ('perf', ['bench-pvm']),
                  'bench-doom': ('perf', ['bench-doom']), 'bench-storage': ('perf', ['bench-storage']),
                  'bench-storage-growth': ('perf', ['bench-storage-growth']),
                  'e2e': ('', []), 'fuzz': ('', []), 'fuzz-pvm': ('', []), 'pvm-backends': ('', [])}
        for suite, (owner, wanted) in manual.items():
            for job in groups:
                rows = selected_families(text, job, event_context('workflow_dispatch', suite=suite))
                self.assertEqual([row['group'] for row in rows], wanted if job == owner else [])
        self.assertNotIn('github.event.pull_request.labels', text)

    def test_combined_pvm_keeps_standalone_modes_and_failure_evidence(self):
        """Full CI runs both suites serially; manual selectors retain their original workload boundaries."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        combined = family_section(text, 'perf', 'bench-pvm-all')
        self.assertLess(combined.index('run: make bench-pvm\n'), combined.index('run: make bench-pvm-doom\n'))
        for suite, group, included, excluded in (
                ('bench-pvm', 'bench-pvm', 'bench-pvm', 'bench-pvm-doom'),
                ('bench-doom', 'bench-doom', 'bench-pvm-doom', 'bench-pvm')):
            # Scheduling conditions retain independent workflow_dispatch controls even with one full-CI family.
            section = family_section(text, 'perf', group,
                context=event_context('workflow_dispatch', suite=suite))
            self.assertIn('run: make '+included+'\n', section)
            self.assertNotIn('run: make '+excluded+'\n', section)
        cancelled = dict(event_context(), cancelled=True)
        stopped = family_section(text, 'perf', 'bench-pvm-all', context=cancelled)
        self.assertNotIn('run: make bench-pvm-doom\n', stopped)
        self.assertIn("if: ${{ !cancelled() && (matrix.family.group == 'bench-doom'", combined)
        for folder in ('pvm-benchmark', 'pvm-doom'):
            self.assertIn('build/tests/'+folder+'/results.json', combined.replace('*.json', 'results.json'))
            self.assertIn('build/tests/'+folder+'/summary.md', combined)

    def test_performance_monitoring_replaces_experiment_jobs(self):
        """Retain regular interpreted comparisons and local tools without historical CI experiments."""
        text=(ROOT/'.github/workflows/ci.yml').read_text()
        for job in ('profile-pvm','profile-doom','compare-doom','compare-pvm','prepared-pvm'):
            self.assertNotIn('  '+job+':\n',text)
        for option in ('pvm_compare_base','pvm_doom_counts_only','pvm_diagnosis',
                       'pvm_build_identity','pvm_deep_attribution'):
            self.assertNotIn(option+':',text)
        self.assertNotIn('ci:pvm-compare',text)
        section=family_section(text,'perf','bench-pvm-all')
        self.assertIn('run: make bench-pvm-doom',section)
        self.assertNotIn('valgrind',section)
        self.assertIn('build/tests/pvm-doom/results.json',section.replace('*.json','results.json'))
        self.assertIn('build/tests/pvm-doom/summary.md',section)
        self.assertNotIn('continue-on-error',section)

    def test_pvm_comparison_runs_with_regular_perf_requests(self):
        """Master and explicit Perf/Full requests include exact-master comparison; ordinary PR updates remain light."""
        text=(ROOT/'.github/workflows/ci.yml').read_text()
        section=job_section(text,'pvm-comparison')
        self.assertIn('name: Perf / PVM Comparison',section)
        self.assertNotIn('Perf / PVM Interpreter Comparison',text)
        guard=job_condition(text,'pvm-comparison')
        enabled=[event_context('push')]
        enabled += [event_context('workflow_dispatch',suite=suite) for suite in ('perf','bench-pvm','full')]
        enabled += [event_context('pull_request',action='labeled',label=label) for label in ('ci:perf','ci:full')]
        disabled=[event_context('pull_request',action='synchronize'),
                  event_context('pull_request',action='labeled',label='ci:unit'),
                  event_context('pull_request',state='closed',label='ci:perf')]
        disabled += [event_context('workflow_dispatch',suite=suite) for suite in ('unit','bench-doom','bench-storage')]
        for context in enabled:
            with self.subTest(context=context): self.assertTrue(expression(guard,context))
        for context in disabled:
            with self.subTest(context=context): self.assertFalse(expression(guard,context))
        self.assertIn('run: make bench-pvm-x86-applications',section)
        self.assertIn('git fetch --no-tags origin master:refs/remotes/origin/master',section)
        self.assertIn('if: always()',section)
        self.assertIn('build/tests/pvm-interpreter-linux/*.json',section)
        self.assertNotIn('continue-on-error',section)

    def test_pvm_native_linux_architectures(self):
        """Both native hosts retain correctness, distinct timing cohorts and unique failure artifacts."""
        text=(ROOT/'.github/workflows/ci.yml').read_text()
        rows=selected_families(text,'pvm-comparison',event_context())
        self.assertEqual([(r['group'],r['os']) for r in rows],
                         [('arm64','ubuntu-26.04-arm'),('x86_64','ubuntu-26.04')])
        for row,target,other in ((rows[0],'bench-pvm-arm64-applications','bench-pvm-x86-applications'),
                                 (rows[1],'bench-pvm-x86-applications','bench-pvm-arm64-applications')):
            # Every architecture uses its own maintained timing driver, after bounded qualification.
            perf=family_section(text,'pvm-comparison',row['group'])
            self.assertIn('run: make check-pvm-native',perf)
            self.assertIn('run: make '+target,perf)
            self.assertNotIn('run: make '+other,perf)
            self.assertIn('pvm-comparison-${{ matrix.family.group }}-',perf)
            self.assertIn('build/tests/pvm-arm64-applications/summary.md',perf)
            self.assertIn('build/tests/pvm-native/*.json',perf)
        self.assertEqual(selected_families(text,'pvm-comparison',event_context('pull_request')),[])
        self.assertIn('check-pvm-native: toolchain check-inventory',(ROOT/'Makefile').read_text())

    def test_workflow_aliases_have_prior_anchors(self):
        """A moved matrix step cannot leave a new standalone experiment referring to a retired alias."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        anchors = set()
        for kind, name in re.findall(r'(?<!\S)([&*])([A-Za-z][\w-]*)', text):
            # GitHub accepts prior YAML anchors; a missing definition makes the entire workflow invalid.
            if kind == '&':
                anchors.add(name)
            else:
                self.assertIn(name, anchors)

    def test_closed_pr_labels_cannot_schedule_or_cancel_ci(self):
        """Closed and merged PR label events schedule no jobs and use an isolated cancellation key."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        jobs = re.findall(r'^  ([\w-]+):\n', text.split('jobs:\n', 1)[1], re.MULTILINE)
        key = re.search(r'^  group: ci-\$\{\{ github.workflow \}\}-\$\{\{ (.*) \}\}$',
                        text, re.MULTILINE).group(1)
        master = event_context()
        master['github'].update(run_id=100, ref='refs/heads/master')
        master_key = expression(key, master)
        seen = set()
        for merged in (False, True):
            # A merged PR can carry a master ref; cancellation isolation cannot rely on ref alone.
            for label in ('ci:full', 'ci:unit', 'ci:docker', 'ci:e2e', 'ci:interop', 'ci:perf', 'ci:fuzz', 'ci:pvm-compare', 'lgtm', 'unrelated'):
                event = event_context('pull_request', 'labeled', label, state='closed', merged=merged)
                event['github'].update(run_id=200+len(seen), ref='refs/heads/master')
                for job in jobs:
                    self.assertFalse(expression(job_condition(text, job), event), (job, merged, label))
                closed_key = expression(key, event)
                self.assertNotEqual(closed_key, master_key)
                self.assertNotIn(closed_key, seen)
                seen.add(closed_key)
        triggers = text.split('"on":\n', 1)[1].split('\npermissions:', 1)[0]
        self.assertNotIn('unlabeled', triggers)

    # Automatic smoke updates and explicit heavy requests use separate cancellation groups.
    def test_ci_request_concurrency(self):
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        expected = ("ci-${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.event.pull_request.state != 'open' && github.run_id || github.event_name == 'pull_request' && github.event.pull_request.state == 'open' && (github.event.action != 'labeled' || github.event.label.name == 'lgtm') && format('smoke-{0}', github.event.pull_request.number) || github.event_name == 'pull_request' && github.event.pull_request.state == 'open' && "
                    "github.event.label.name != 'ci:unit' && github.event.label.name != 'ci:full' && github.event.label.name != 'ci:docker' && "
                    "github.event.label.name != 'ci:e2e' && github.event.label.name != 'ci:interop' && github.event.label.name != 'ci:perf' && github.event.label.name != 'ci:fuzz' && github.run_id || github.ref }}")
        self.assertIn('group: '+expected+'\n  cancel-in-progress: true', text)

    # The Unit matrix covers every partition once with independently named results.
    def test_ci_unit_partitions(self):
        from native_tests import parse_unit_shard
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        from workflow_fixtures import selected_families, event_context
        families = selected_families(text, 'unit', event_context())
        self.assertEqual(len(families), 20)
        corpus = [row for row in families if row['group'] == 'corpus']
        self.assertEqual(corpus, [dict(name=f'Corpus ({index}/4)', shard='', group='corpus',
                                     corpus_shard=f'{index}/4') for index in (1, 2, 3, 4)])
        values = [row['shard'] for row in families if row['group'] == 'suites']
        partitions = [parse_unit_shard(value) for value in values]
        count = partitions[0][1]
        self.assertEqual(count, 16)
        self.assertEqual(partitions, [(index, count) for index in range(1, count+1)])
        unit = job_section(text, 'unit')
        self.assertIn('CI_SHARD_SEED: ${{ github.run_id }}', unit)
        self.assertIn('max-parallel: 20', unit)
        self.assertIn('CORPUS_SHARD: ${{ matrix.family.corpus_shard }}', unit)
        self.assertIn('build/tests/corpus/*/results.json', unit)
        self.assertIn('name: Unit / ${{ matrix.family.name }}', unit)
        self.assertIn('UNIT_SCOPE: ${{ matrix.family.group }}', unit)
        self.assertIn('UNIT_SHARD: ${{ matrix.family.shard }}', unit)
        self.assertIn('build/tests/corpus/results.json', unit)
        for context in (event_context(event='workflow_dispatch', suite='unit'),
                        event_context(event='pull_request', action='labeled', label='ci:unit'),
                        event_context(event='pull_request', action='labeled', label='ci:full')):
            # The corpus row cannot disappear from a requested Unit run or add an extra skipped PR job.
            self.assertEqual(selected_families(text, 'unit', context), families)
        self.assertEqual(selected_families(text, 'unit', event_context(event='pull_request')), [])

    def test_promoted_interpreter_has_one_native_ci_path(self):
        """The production engine is qualified through discovered native suites, with no duplicate overlay job."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        self.assertNotIn('  pvm-experimental:',text)
        self.assertNotIn('  pvm-sanitizers:',text)
        families = selected_families(text,'unit',event_context())
        self.assertFalse(any(row['group'] == 'pvm-asan' for row in families))
        for group in ('suites', 'corpus'):
            # Every unit worker uses the shared executor and Markdown renderer, including failed ASan.
            native = family_section(text, 'unit', group)
            self.assertIn('run: make check-unit', native)
            self.assertIn('run: make summary-', native)
            self.assertNotIn('run: make check-pvm-asan', native)
            for evidence in ('build/tests/pvm-asan/*.log', 'build/tests/pvm-asan/results.json',
                             'build/tests/pvm-asan/evidence/*.json', 'build/tests/runtime/summary.md'):
                self.assertIn(evidence, native)
        self.assertIn('run: make check-unit',text)
        for path in (ROOT/'tests/unit/codec').glob('test_pvm_stream_*.nim'):
            # Inventory validates every ordinary witness's requirements and exact output contract.
            self.assertTrue(path.with_suffix('.output').is_file())
            self.assertTrue((ROOT/'tools/native_requirements/codec'/(path.stem[5:]+'.json')).is_file())

    # Every contract partition retains its independently named workload.
    def test_ci_contract_partitions(self):
        from failure_plans import parse_failure_shard
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = job_section(text, 'failures')
        values = json.loads('['+re.search(r'        shard: \[([^\n]+)\]', section).group(1)+']')
        partitions = [parse_failure_shard(value) for value in values]
        count = partitions[0][1]
        self.assertEqual(count, 6)
        self.assertEqual(partitions, [(index, count) for index in range(1, count+1)])
        self.assertIn('FAILURE_SHARD: ${{ matrix.shard }}', section)
        self.assertIn('CI_SHARD_SEED: ${{ github.run_id }}', section)

    def test_ci_e2e_families(self):
        """Every declared E2E family runs independently with its own result and diagnostics."""
        from e2e_checks import PLAN
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = job_section(text, 'e2e')
        groups = tuple(row['group'] for row in selected_families(text, 'e2e', event_context()))
        self.assertEqual(tuple(group for group in groups if group != 'mcp'), PLAN.groups())
        self.assertIn('mcp', groups)
        self.assertIn('fail-fast: false', section)
        self.assertIn('E2E_GROUP: ${{ matrix.family.group }}', section)
        self.assertIn('name: E2E / ${{ matrix.family.name }}', section)
        self.assertIn('name: ${{ matrix.os }}-e2e-${{ matrix.family.group }}-${{ github.run_attempt }}', section)
        for diagnostic in ('result.json','independent/plan.json','node-*/*.log','node-*/head.json'):
            self.assertIn('build/tests/e2e/tiny-devnet-*/'+diagnostic, section)
        self.assertNotIn('build/tests/e2e/tiny-devnet-*/**', section)
        self.assertNotIn('node-*/*.pem', section) # Retain narrow diagnostics rather than TLS key directories.
        self.assertNotIn('needs:', section)

    def test_logical_groups_have_no_aggregate_runners(self):
        """Display groups retain named workloads without runner-only result aggregators."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        jobs = re.findall(r'^  ([\w-]+):\n', text.split('jobs:\n', 1)[1], re.MULTILINE)
        self.assertEqual(jobs, ['build', 'unit', 'failures', 'e2e', 'interop',
                                'pvm-doom-backends', 'perf', 'pvm-comparison', 'pvm-fuzz'])
        self.assertNotIn('needs:', text)
        for job, group in [('build', 'Build'), ('unit', 'Unit'), ('failures', 'Contract'),
                           ('e2e', 'E2E'), ('interop', 'Interop'), ('pvm-doom-backends', 'Interop'),
                           ('perf', 'Perf'), ('pvm-comparison', 'Perf'), ('pvm-fuzz', 'Fuzz')]:
            self.assertIn('    name: '+group+' / ', job_section(text, job))
            self.assertIn('  # '+group+' group:', text)

    def test_binary_builds_match_pinned_hosts_and_publish_only_archives(self):
        """Linux owns its native archive and isolated Docker build; macOS keeps its qualified host."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = family_section(text, 'build', 'binary', 'Linux & Docker')
        rows = selected_families(text, 'build', event_context())
        binary = [row for row in rows if row['group'] == 'binary']
        pins = json.loads((ROOT/'spec/toolchain.json').read_text())
        # Available compiler archives also serve local experiments; CI release hosts are qualified explicitly.
        archive_hosts = {'Linux & Docker': ('linux-amd64', 'Linux', 'x86_64'),
                         'macOS': ('macos-arm64', 'Darwin', 'arm64')}
        self.assertEqual({row['name']: row['platform'] for row in binary},
                         {name: values[0] for name, values in archive_hosts.items()})
        for row in binary:
            # Every exact release target still needs its matching immutable compiler and host architecture.
            selected = pins['platforms'][row['platform'].replace('-', '_')]
            _, system, machine = archive_hosts[row['name']]
            self.assertEqual(selected['system'], system)
            self.assertIn(machine, selected['machines'])
        self.assertEqual([(row['name'], row.get('os') or re.search(r'&ubuntu-x86-version ([\w.-]+)', text).group(1)) for row in binary],
                         [('Linux & Docker', 'ubuntu-26.04'), ('macOS', 'macos-15')])
        self.assertIn('fail-fast: false', section)
        self.assertIn('name: Build / ${{ matrix.family.name }}', section)
        self.assertIn('run: make package-binary', section)
        self.assertIn('run: make check-docker', section)
        self.assertIn('if-no-files-found: error', section)
        self.assertIn('build/dist/ragnarok-${{ matrix.family.platform }}.tar.gz.sha256', section)
        self.assertNotIn('contents: write', text)
        self.assertNotIn('needs:', section)
        make = (ROOT/'Makefile').read_text()
        self.assertIn('package-binary: export BINARY_PACKAGE = 1', make)
        self.assertIn('package-binary: build\n\t$(PYTHON) tools/package_binary.py', make)
        self.assertIn('if [ "$(BINARY_PACKAGE)" = 1 ]; then packages="$$packages patchelf"; fi;', make)

    def test_linux_docker_runner_and_focused_requests(self):
        """Full Build reuses one Linux runner; Docker-only requests and failure evidence stay scoped."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        linux = family_section(text, 'build', 'binary', 'Linux & Docker')
        macos = family_section(text, 'build', 'binary', 'macOS')
        self.assertEqual(linux.count('run: make package-binary\n'), 1)
        self.assertEqual(linux.count('run: make check-docker\n'), 1)
        self.assertLess(linux.index('run: make package-binary\n'), linux.index('run: make check-docker\n'))
        self.assertNotIn('run: make check-docker', macos)
        self.assertIn('FROM ubuntu:24.04@', (ROOT/'Dockerfile').read_text())
        self.assertIn('build\n', (ROOT/'.dockerignore').read_text())
        for context in (event_context('workflow_dispatch', suite='docker'),
                        event_context('pull_request', 'labeled', 'ci:docker')):
            # The pre-existing Docker-only selector never expands into either native archive build.
            rows = selected_families(text, 'build', context)
            self.assertEqual(rows, [dict(name='Docker', group='docker', platform='')])
            focused = family_section(text, 'build', 'docker', context=context)
            self.assertEqual(focused.count('run: make check-docker\n'), 1)
            self.assertNotIn('run: make package-binary', focused)
            self.assertNotIn('name: Retain downloadable binary archive', focused)
            for job in ('interop', 'perf'):
                # Label-triggered Docker validation cannot accidentally request an unrelated heavy group.
                if context['github']['event_name'] == 'pull_request':
                    self.assertEqual(selected_families(text, job, context), [])
        for path in ('build/ci/docker-build.log', 'build/ci/docker-smoke.log',
                     'build/ci/*.log', 'build/crypto/build.log', 'build/quic/build.log'):
            self.assertIn(path, linux)
        self.assertIn('name: docker-${{ github.run_attempt }}', linux)
        self.assertIn('name: binary-${{ matrix.family.platform }}-diagnostics-', linux)
        self.assertNotIn('continue-on-error', linux)
        self.assertIn("if: ${{ !cancelled() && (matrix.family.group == 'docker'", linux)
        cancelled = family_section(text, 'build', 'binary', 'Linux & Docker',
                                   context=dict(event_context(), cancelled=True))
        self.assertNotIn('run: make check-docker', cancelled)
        # The explicit status condition lets Docker execute after a failed earlier archive/summary step.
        step = linux.split('      - name: Build and smoke-test Docker image\n', 1)[1].split('      - name:', 1)[0]
        guard = re.search(r'        if: (.+)', step).group(1)
        self.assertTrue(expression(guard, dict(event_context(), cancelled=False,
            matrix=dict(family=dict(group='binary', platform='linux-amd64')))))

    def test_tooling_preserves_independent_model_checks(self):
        """Models share Tooling's runner while retaining scheduling, failure evidence and strict results."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        self.assertNotIn('\n  models:\n', text)
        tooling = family_section(text, 'build', 'python')
        self.assertIn('run: make check-models', tooling)
        self.assertIn('run: make summary-models SUMMARY_OUTPUT="$GITHUB_STEP_SUMMARY"', tooling)
        for path in ('build/ci/model-tools.log', 'build/ci/models.log', 'build/ci/setup.log',
                     'build/tests/models/*.log', 'build/tests/models/*.nif',
                     'build/tests/models/results.json'):
            self.assertIn(path, tooling)
        step = re.search(r'      - name: Check lifecycle.*?(?=      - name:)',
                         tooling, re.DOTALL).group(0)
        guard = re.search(r'^        if: (.+)$', step, re.MULTILINE).group(1)
        # A prior Python failure must not suppress model checks; cancellation may stop expensive work.
        for cancelled in (False, True):
            context = dict(event_context(), matrix=dict(family=dict(group='python')), cancelled=cancelled)
            self.assertEqual(expression(guard, context), not cancelled)
        for group in ('smoke', 'binary', 'checks', 'docker'):
            context = dict(event_context(), matrix=dict(family=dict(group=group)))
            self.assertFalse(expression(guard, context))
        # Rejection checks share this runner and retain strict evidence after other Tooling failures.
        self.assertIn('run: make check-guards', tooling)
        self.assertIn('run: make summary-guards SUMMARY_OUTPUT="$GITHUB_STEP_SUMMARY"', tooling)
        self.assertIn('build/tests/guards/results.json', tooling)
        rejection = next(s for s in re.findall(r'^      - .*?(?=^      - |\Z)', tooling, re.M | re.S)
                         if 'run: make check-guards\n' in s)
        rejection_guard = re.search(r'^        if: (.+)$', rejection, re.MULTILINE).group(1)
        self.assertEqual(rejection_guard, guard)
        self.assertNotIn('continue-on-error', tooling)

    # Every independent CI job must visibly reject incomplete inventories before provisioning its workload.
    def test_ci_inventory_preflight(self):
        """Every native matrix family validates inventory before its own provisioning command."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        self.assertIn('run: &inventory-run make check-inventory', text)
        for job, family, target in [('build', 'binary', 'check-modules'), ('build', 'python', 'check-python'),
                                    ('build', 'python', 'check-models'),
                                    ('build', 'python', 'check-guards'), ('interop', 'pvm-reference', 'check-pvm-reference'),
                                    ('interop', 'telemetry-interop', 'check-telemetry-interop-ci'),
                                    ('e2e', 'mcp', 'check-mcp-interop'),
                                    ('perf', 'bench-pvm-all', 'bench-pvm'), ('perf', 'bench-storage', 'bench-storage'),
                                    ('perf', 'bench-storage', 'bench-storage-growth'), ('build', 'binary', 'check-docker')]:
            section = family_section(text, job, family)
            self.assertEqual(section.count('name: Validate verification inventory'), 1)
            self.assertLess(section.index('name: Validate verification inventory'), section.index('run: make '+target))
        for job in ('unit', 'failures', 'e2e', 'pvm-fuzz'):
            self.assertIn('run: *inventory-run', job_section(text, job))
        self.assertNotIn('continue-on-error:', text)

    def test_mcp_interop_keeps_real_sdk_and_wire_evidence(self):
        """MCP joins the required E2E matrix with explicit message evidence and no test-key upload."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = family_section(text, 'e2e', 'mcp')
        self.assertIn('run: make check-mcp-interop', section)
        self.assertIn("always() && matrix.family.group == 'mcp'", section)
        self.assertIn('build/tests/mcp-interop/results.json', section)
        self.assertIn('build/tests/mcp-interop/*/*.jsonl', section)
        self.assertNotIn('build/tests/mcp-interop/**\n', section)
        self.assertNotIn('build/mcp-interop-python', section)
        self.assertNotIn('continue-on-error:', section)
        self.assertNotIn('run: make check-e2e', section)
        self.assertNotIn('run: make summary-${{ github.job }}', section)
        # Heavy SDK execution follows E2E requests, independently of Interop labels.
        for label, expected in [('ci:e2e', True), ('ci:full', True), ('ci:interop', False)]:
            rows = selected_families(text, 'e2e', event_context('pull_request', 'labeled', label))
            self.assertEqual(any(row['group'] == 'mcp' for row in rows), expected)

    def test_pvm_reference_evidence_scope(self):
        """The separate full-scope job keeps failed-run evidence without silently allowing failure."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = family_section(text, 'interop', 'pvm-reference')
        self.assertIn('runs-on: ${{ matrix.os }}', section)
        self.assertIn('os: *ci-os', section)
        self.assertIn('RAGNAROK_PVM_REFERENCE_BACKEND: interpreter', section)
        self.assertNotIn('sysctl', section)
        self.assertIn("inputs.suite == 'interop'", section)
        self.assertIn("github.event.label.name == 'ci:interop'", section)
        self.assertEqual(section.count('run: make check-pvm-reference'), 1)
        artifact = section.split('      - name: Retain PVM comparison evidence\n', 1)[1]
        self.assertIn("if: ${{ always() && matrix.family.group == 'pvm-reference' }}", artifact)
        self.assertIn('uses: *upload-artifact', artifact)
        paths = section.split('          path: |\n', 1)[1]
        self.assertIn('build/tests/pvm-reference/results.json', paths)
        self.assertIn('build/tests/pvm-reference/summary.md', paths)
        self.assertIn('run: make summary-pvm-reference SUMMARY_OUTPUT="$GITHUB_STEP_SUMMARY"', section)
        self.assertIn('build/tests/pvm-reference/*.log', paths)
        self.assertNotIn('**', paths)
        self.assertNotIn('target', paths)
        self.assertNotIn('.bin', paths)
        self.assertNotIn('continue-on-error', section)
        self.assertNotIn('needs:', section)

    def test_benchmark_runs_on_master_and_perf_requests_with_raw_data(self):
        """Master/group requests retain the Actions table and raw validated measurements."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = family_section(text, 'perf', 'bench-pvm-all')
        self.assertEqual([row['group'] for row in selected_families(text, 'perf',
                         event_context('workflow_dispatch', suite='bench-pvm'))], ['bench-pvm'])
        self.assertEqual(section.count('run: make bench-pvm\n'), 1)
        for target in ('bench-pvm-sieve','bench-pvm-guests'):
            self.assertEqual(section.count('run: make '+target+'\n'),1)
        self.assertIn('build/tests/pvm-sieve/summary.md build/tests/pvm-guests/summary.md',section)
        for folder in ('pvm-sieve','pvm-guests'):
            for name in ('results.json','samples.csv','summary.md'):
                self.assertIn('build/tests/'+folder+'/'+name,section)
        self.assertIn('build/tests/pvm-guests/*/*.log',section)
        self.assertNotIn('pvm-ir',section)
        self.assertLess(section.index('name: Validate verification inventory'), section.index('run: make bench-pvm'))
        self.assertIn('summary-pvm-benchmark SUMMARY_OUTPUT="$GITHUB_STEP_SUMMARY"', section)
        for name in ('results.json','samples.csv','summary.md'):
            self.assertIn('build/tests/pvm-benchmark/'+name, section)
        self.assertNotIn('continue-on-error', section)
        self.assertNotIn('sysctl', section)

    # Interop jobs remain adjacent in the workflow and use consistent group names in Actions.
    def test_one_matrix_per_display_group(self):
        """Each group has one real matrix job, rather than same-name independent skipped jobs."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        for group, names in [('interop', ['PVM', 'Telemetry']), ('perf', ['PVM', 'Storage']),
                             ('build', ['Smoke', 'Tooling', 'Linux & Docker', 'macOS'])]:
            self.assertEqual([row['name'] for row in selected_families(text, group, event_context())], names)
            self.assertIn('name: '+group.title()+' / ${{ matrix.family.name }}', job_section(text, group))
            self.assertEqual(text.count('    name: '+group.title()+' / ${{ matrix.family.name }}'), 1)
        for removed in ('compile', 'compile-status', 'smoke', 'modules', 'python', 'guards', 'pvm-reference', 'telemetry-interop',
                        'bench-pvm', 'bench-storage', 'bench-storage-growth', 'docker', 'binary'):
            self.assertNotIn('\n  '+removed+':\n', text)

    def test_storage_perf_scope_and_summary(self):
        """Storage shares the Perf group while retaining independent validated artifacts and failure status."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = family_section(text, 'perf', 'bench-storage')
        for trigger in ("github.event_name == 'push'", "inputs.suite == 'perf'", "inputs.suite == 'bench-storage'",
                        "inputs.suite == 'full'", "github.event.label.name == 'ci:perf'", "github.event.label.name == 'ci:full'"):
            self.assertIn(trigger, section)
        self.assertEqual(section.count('run: make bench-storage\n'), 1)
        self.assertIn('summary-storage-benchmark SUMMARY_OUTPUT="$GITHUB_STEP_SUMMARY"', section)
        self.assertIn('always()', section)
        for name in ('results.json', 'samples.csv', 'summary.md'):
            self.assertIn('build/tests/storage-benchmark/'+name, section)
        self.assertNotIn('continue-on-error', section)
        self.assertNotIn('needs:', section)

    def test_storage_growth_shares_the_storage_runner(self):
        """One full-request family retains both panels, separate evidence and scoped manual dispatches."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        full = family_section(text, 'perf', 'bench-storage')
        comparison = family_section(text, 'perf', 'bench-storage', context=event_context(
            'workflow_dispatch', suite='bench-storage'))
        growth = family_section(text, 'perf', 'bench-storage-growth', context=event_context(
            'workflow_dispatch', suite='bench-storage-growth'))
        for context in (event_context(), event_context('workflow_dispatch', suite='perf'),
                        event_context('workflow_dispatch', suite='full'),
                        event_context('pull_request', 'labeled', 'ci:perf'),
                        event_context('pull_request', 'labeled', 'ci:full')):
            # Group requests allocate one Storage runner and execute both original commands once.
            families = selected_families(text, 'perf', context)
            self.assertEqual([row['name'] for row in families], ['PVM', 'Storage'])
            section = family_section(text, 'perf', 'bench-storage', context=context)
            self.assertEqual(section.count('run: make bench-storage\n'), 1)
            self.assertEqual(section.count('run: make bench-storage-growth\n'), 1)
        self.assertIn('run: make bench-storage\n', comparison)
        self.assertNotIn('run: make bench-storage-growth\n', comparison)
        self.assertIn('run: make bench-storage-growth\n', growth)
        for command in ('bench-storage', 'bench-storage-memory-ceilings', 'bench-storage-resources'):
            # Growth-only requests keep their original workload rather than silently expanding scope.
            self.assertNotIn('run: make '+command+'\n', growth)
        self.assertNotIn('Storage Growth', job_section(text, 'perf'))
        for section in (full, growth):
            # A failed short/resource panel cannot suppress growth; cancellation still stops work.
            self.assertIn("if: ${{ !cancelled() && (matrix.family.group == 'bench-storage-growth'", section)
            self.assertIn('summary-storage-growth SUMMARY_OUTPUT="$GITHUB_STEP_SUMMARY"', section)
            self.assertIn('name: bench-storage-growth-${{ github.run_attempt }}', section)
            self.assertIn('timeout-minutes: *ci-job-timeout', section)
            for name in ('results.json', 'summary.md', 'growth/results.json', 'growth/samples.csv',
                         'growth/publications.csv', 'growth/io/*.log', 'growth/io/results.json', 'growth/io/calls.csv'):
                self.assertIn('build/tests/storage-growth-benchmark/'+name, section)
            self.assertNotIn('continue-on-error', section)
            self.assertNotIn('needs:', section)
        self.assertLess(full.index('run: make bench-storage\n'), full.index('run: make bench-storage-growth\n'))
        growth_step = full.split('      - name: Measure sustained storage growth and SDK IO\n', 1)[1].split('      - name:', 1)[0]
        guard = re.search(r'        if: (.+)', growth_step).group(1)
        for cancelled in (False, True):
            # The explicit status function overrides implicit success() after an earlier step failure.
            context = dict(event_context(), matrix=dict(family=dict(group='bench-storage')),
                           cancelled=cancelled)
            self.assertEqual(expression(guard, context), not cancelled)

    # The shared native builder must work before any historical driver has created its output directory.
    def test_bandersnatch_clean_build_directory(self):
        with temporary_folder() as temporary:
            folder = temporary/'build/bandersnatch'
            features = 'secret-split\n'
            outputs = ['rustc '+bandersnatch.PINS['rust']+' fixture',
                       'cargo '+bandersnatch.PINS['rust']+' fixture', features]
            with patch.object(bandersnatch, 'BUILD', folder), patch.object(
                    bandersnatch.subprocess, 'check_output', side_effect=outputs), patch.object(
                    bandersnatch, 'run') as run:
                library = bandersnatch.build_native(False)
                # Reusing the same directory must also succeed, without fetching dependencies.
                with patch.object(bandersnatch.subprocess, 'check_output', side_effect=outputs):
                    self.assertEqual(bandersnatch.build_native(False), library)
            self.assertTrue((folder/'build.log').is_file())
            self.assertEqual((folder/'cargo-features.log').read_text(), features)
            self.assertEqual(library.parent, folder/'target/release')
            self.assertEqual([call.args[0][1] for call in run.call_args_list],
                             ['fmt', 'test', 'build']*2)
            for call in (run.call_args_list[1], run.call_args_list[4]):
                # Adapter tests must share the shipped release profile instead of building debug dependencies.
                self.assertIn('--release', call.args[0])

    # The same immutable nightly revision must select the correct platform archive and reject unknown hosts.
    def test_local_and_ci_host_selection(self):
        pins = json.loads((ROOT/'spec/toolchain.json').read_text())
        for system, machine, name in (('Linux', 'x86_64', 'linux_amd64'), ('Linux', 'aarch64', 'linux_arm64'),
                                      ('Linux', 'arm64', 'linux_arm64'), ('Darwin', 'arm64', 'macos_arm64')):
            # Host selection changes archive identity, never the selected compiler revision.
            with self.subTest(system=system):
                selected = host_pins(pins, system, machine)
                self.assertEqual(selected['platform'], name)
                self.assertEqual(selected['commit'], pins['commit'])
                self.assertIn('sha256', selected['formatter_download'])
        with self.assertRaises(ValueError):
            host_pins(pins, 'Linux', 'unknown')

    # Local and CI entry points must retain native runtime, every-source audit and all independent Python harnesses.
    def test_supported_command_plan(self):
        command = ['make', '--no-print-directory', '-n']
        runtime = subprocess.check_output(command+['check-unit'], cwd=ROOT, text=True)
        module_plan = subprocess.check_output(command+['check-modules'], cwd=ROOT, text=True)
        self.assertIn('tools/test_runtime.py', runtime)
        corpus = subprocess.check_output(command+['check-corpus'], cwd=ROOT, text=True)
        self.assertEqual(corpus.count('tools/test_runtime.py'), 1)
        self.assertIn('UNIT_SCOPE := corpus', (ROOT/'Makefile').read_text())
        summary = subprocess.check_output(command+['summary-unit', 'UNIT_SCOPE=corpus'], cwd=ROOT, text=True)
        self.assertIn('build/tests/corpus/results.json', summary)
        self.assertIn('tools/setup_submodules.py', runtime)
        self.assertIn('cargo fetch --locked', runtime)
        self.assertNotIn('unittest discover', runtime)
        self.assertIn('tools/test_modules.py', module_plan)
        self.assertNotIn('cargo fetch', module_plan)
        self.assertNotIn('tools/test.py', runtime+module_plan)
        python_plan = subprocess.check_output(command+['check-python'], cwd=ROOT, text=True)
        self.assertIn('tools/test_python.py', python_plan)
        self.assertNotIn('setup_nimony.py', python_plan)
        self.assertNotIn('cargo', python_plan)
        self.assertNotIn('tools/test_e2e.py', runtime)
        complete = subprocess.check_output(command+['check'], cwd=ROOT, text=True)
        for runner in ('test_models', 'test_python', 'test_modules', 'test_guards', 'test_e2e'):
            # Complete local verification owns exactly one invocation of every independently selectable group.
            self.assertEqual(complete.count('tools/'+runner+'.py'), 1)
        self.assertEqual(complete.count('tools/check_jam_fuzzer_interface.py'), 1)
        self.assertEqual(complete.count('tools/test_runtime.py'), 2)
        self.assertEqual(complete.count('--group failures'), 1)
        failures = subprocess.check_output(command+['check-failures'], cwd=ROOT, text=True)
        self.assertIn('--group failures', failures)
        self.assertNotIn('--group failures', runtime)

    # A fresh failed Python group must publish failure rather than reuse stale successful discovery.
    def test_python_gate_failure(self):
        import test_python
        with temporary_folder() as folder:
            (folder/'results.json').write_text(json.dumps(dict(status='checks-passed')))
            failed = dict(command=['fixture'], exit_code=7, log='fixture.log', output='failed test')
            with patch.object(test_python, 'BUILD', folder), patch.object(
                    test_python, 'NativeChecks') as runner, patch('sys.stdout', new_callable=io.StringIO) as output:
                runner.return_value.command.return_value = failed
                with self.assertRaises(SystemExit) as stopped:
                    test_python.main()
            self.assertEqual(stopped.exception.code, 1)
            self.assertIn('failed test', output.getvalue())
            self.assertIn('FAIL Python verification', output.getvalue())
            self.assertEqual(runner.return_value.command.call_count, 1)
            self.assertIn('test_*.py', runner.return_value.command.call_args.args[0])
            self.assertEqual(runner.return_value.command.call_args.kwargs['timeout'], 1800)
            report = json.loads((folder/'results.json').read_text())
            self.assertEqual(report['status'], 'failed')
            self.assertEqual(report['check']['exit_code'], 7)
            self.assertEqual(report['tests'], 0)

    # Independent compiler probes may overlap but preserve ordered records and private caches/logs.
    def test_parallel_rejection_isolation(self):
        import test_guards
        barrier = threading.Barrier(2)
        calls = []
        # A barrier requires actual overlap without depending on host speed or arbitrary sleep thresholds.
        def fake_command(arguments, name):
            calls.append((name, arguments))
            if name.startswith('cache-control-'):
                return dict(exit_code=0, output='')
            barrier.wait(timeout=5)
            return dict(exit_code=1, output=name)
        with patch.dict(test_guards.os.environ, {'COMPILE_CHECK_JOBS': '2'}), patch.object(
                test_guards, 'command', side_effect=fake_command):
            rows = list(test_guards.compile_rejections(Path('/fixture/nimony'), {'first': 'a', 'second': 'b'}))
        self.assertEqual([(name, expected) for name, expected, _ in rows], [('first', 'a'), ('second', 'b')])
        self.assertEqual({name for name, _ in calls if not name.startswith('cache-control-')},
                         {'first', 'second'})
        caches = {arg for _, arguments in calls for arg in arguments if str(arg).startswith('--nimcache:')}
        self.assertEqual(len(caches), 2)
        self.assertTrue(all(row[2]['exit_code'] == 1 for row in rows))
        with patch.dict(test_guards.os.environ, {'COMPILE_CHECK_JOBS': '0'}):
            # A zero worker count cannot silently omit the rejection registry.
            with self.assertRaisesRegex(ValueError, 'COMPILE_CHECK_JOBS'):
                list(test_guards.compile_rejections(Path('/fixture/nimony'), {}))

    # Extracting a formatter archive must expose only nimpretty, with safe repeated symlink handling.
    def test_formatter_only_installation(self):
        with temporary_folder() as folder:
            compiler, formatter = folder/'compiler', folder/'formatter'
            for relative in ('bin/nimony', 'bin/nifmake', 'bin/niflink', 'bin/hastur', 'lib/std/system.nim'):
                # Inert fixture files exercise layout validation; no fabricated compiler is executed.
                path = compiler/relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('fixture')
            (compiler/'NIGHTLY.txt').write_text('nimony-commit: pinned\ndate: today\nplatform: fixture\n')
            (formatter/'bin').mkdir(parents=True)
            (formatter/'bin/nimpretty').write_text('formatter fixture')
            pins = dict(commit='pinned', date='today', platform='fixture', download={'sha256': 'c'*64}, formatter_download={'sha256': 'f'*64})
            with patch('setup_nimony.download', return_value=b'fixture') as downloaded, patch(
                    'setup_nimony.extract', side_effect=[compiler, formatter]*3):
                root, paths, metadata = install(folder/'tools', pins)
                self.assertEqual(downloaded.call_args_list[0].args[1].name, 'nimony-'+('c'*64)+'.archive')
                self.assertEqual(downloaded.call_args_list[1].args[1].name, 'formatter-'+('f'*64)+'.archive')
                self.assertEqual(paths, [compiler/'bin', folder/'tools/formatter-bin'])
                self.assertNotIn(formatter/'bin', paths)
                self.assertEqual((paths[1]/'nimpretty').resolve(), (formatter/'bin/nimpretty').resolve())
                install(folder/'tools', pins)
                (paths[1]/'nimpretty').unlink()
                (paths[1]/'nimpretty').write_text('unrelated file')
                with self.assertRaisesRegex(ValueError, 'unrelated'):
                    install(folder/'tools', pins)

    # Normal local verification must reject modified tools and changed pins before running any workload.
    def test_installed_binary_integrity(self):
        with temporary_folder() as folder:
            compiler, formatter = folder/'nimony', folder/'nimpretty'
            compiler.write_bytes(b'compiler fixture')
            formatter.write_bytes(b'formatter fixture')
            digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
            manifest = dict(compiler=str(compiler), formatter=str(formatter),
                            compiler_sha256=digest(compiler), formatter_sha256=digest(formatter),
                            pins_sha256=digest(ROOT/'spec/toolchain.json'))
            (folder/'environment.json').write_text(json.dumps(manifest))
            with patch('setup_nimony.verify_identity'), patch('setup_nimony.verify_version'):
                self.assertEqual(installed(folder), (compiler, formatter))
                formatter.write_bytes(b'changed formatter')
                with self.assertRaisesRegex(ValueError, 'formatter'):
                    installed(folder)
                compiler.write_bytes(b'changed compiler')
                with self.assertRaisesRegex(ValueError, 'compiler'):
                    installed(folder)

    # Same-version compilers at different paths cannot reuse Nimony dependency indexes from an old installation.
    def test_compiler_location_cache_isolation(self):
        folder = Path('/fixture/results')
        before = cache_directory(Path('/fixture/old/bin/nimony'), folder, 'codec')
        after = cache_directory(Path('/fixture/new/bin/nimony'), folder, 'codec')
        self.assertNotEqual(before, after)
        self.assertEqual(after, cache_directory(Path('/fixture/new/bin/nimony'), folder, 'codec'))
        self.assertEqual(after.parent.parent, folder)

    # A stale/corrupt retained download must fail without trusting its filename or using the network.
    def test_cached_checksum_mismatch(self):
        with temporary_folder() as temporary:
            path = temporary/'tool.archive'
            path.write_bytes(b'changed bytes')
            with patch('urllib.request.urlopen', side_effect=AssertionError('unexpected network')):
                with self.assertRaises(ValueError):
                    download(dict(url='https://example.invalid/release', sha256='0'*64), path)

    # Data filtering must reject traversal rather than create a file outside the installation directory.
    def test_archive_traversal(self):
        with temporary_folder() as root:
            with self.assertRaises(tarfile.FilterError):
                extract(archive('tool/../../escaped'), root/'install')
            self.assertFalse((root/'escaped').exists())

    # Multiple archive roots must fail before any files are extracted into runner storage.
    def test_archive_multiple_roots(self):
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode='w') as tar:
            # Independent roots are an unexpected asset layout, not a usable binary path.
            for name in ('first/tool', 'second/tool'):
                member = tarfile.TarInfo(name)
                tar.addfile(member)
        with temporary_folder() as temporary:
            with self.assertRaises(ValueError):
                extract(data.getvalue(), temporary)
            self.assertEqual(list(temporary.iterdir()), [])

    def test_all_source_profiles_and_failed_compilations(self):
        """Every discovered module is imported, debug skips optimization, and either compiler failure stays red."""
        with temporary_folder() as root:
            (root/'src').mkdir()
            for name in ('ragnarok.nim', 'unimported.nim'):
                (root/'src'/name).write_text('discard')
            caches = []
            for smoke in (True, False):
                for codes in ((0, 0), (7, 0), (0, 7)):
                    outputs = [subprocess.CompletedProcess([], code, '', 'diagnostic') for code in codes]
                    with self.subTest(smoke=smoke, codes=codes), patch.object(modules, 'ROOT', root), patch.object(
                            modules.subprocess, 'check_output', return_value='fixture'), patch.object(
                            modules.subprocess, 'run', side_effect=outputs) as command, patch('sys.stdout'):
                        report = modules.audit(root/'compiler', root/'evidence', smoke=smoke)
                    self.assertEqual([row['source'] for row in report['modules']], ['src/ragnarok.nim', 'src/unimported.nim'])
                    self.assertEqual(report['jobs'], 1)
                    self.assertEqual(report['profile'], 'debug-unoptimized' if smoke else 'checked-release')
                    self.assertEqual(report['status'] == 'compile-checks-passed', codes == (0, 0))
                    self.assertEqual(command.call_count, 2)
                    imports = (root/'evidence/all_sources.nim').read_text()
                    self.assertIn(str(root/'src/unimported.nim'), imports)
                    self.assertEqual(len([line for line in imports.splitlines() if line.startswith('import ')]), 2)
                    for call in command.call_args_list:
                        arguments = call.args[0]
                        for flag in ('check', '--mm:arc', '--boundchecks:on'):
                            self.assertIn(flag, arguments)
                        self.assertEqual('--opt:none' in arguments, smoke)
                        self.assertEqual('-d:release' in arguments, not smoke)
                        self.assertEqual('--passC:-flto=thin' in arguments, not smoke)
                        caches.append(next(value for value in arguments if value.startswith('--nimcache:')))
                    main = command.call_args_list[-1].args[0]
                    for flag in ('--isMain', '-d:integration', '-d:offload'):
                        self.assertIn(flag, main)
            self.assertEqual(len(set(caches)), len(caches))
            (root/'src/ragnarok.nim').unlink()
            with patch.object(modules, 'ROOT', root):
                with self.assertRaisesRegex(ValueError, 'peer entry point'):
                    modules.audit(root/'compiler', root/'evidence', smoke=True)
            self.assertFalse((root/'evidence/results.json').exists())

    # Same-version archives for a different platform or commit are not accepted as the selected nightly.
    def test_identity_mismatch(self):
        pins = host_pins(json.loads((ROOT/'spec/toolchain.json').read_text()), 'Linux', 'x86_64')
        with temporary_folder() as root:
            (root/'NIGHTLY.txt').write_text('nimony-commit: '+pins['commit']+'\ndate: '+pins['date']+'\nplatform: macos_arm64\n')
            with self.assertRaisesRegex(ValueError, 'platform'):
                verify_identity(root, pins)

    # Real child processes reproduce stdout/stderr behavior without downloading or executing a fixture compiler.
    def test_version_streams_and_rejections(self):
        real_output = subprocess.check_output
        # Both supported stream placements must pass; a wrong/empty banner or failing command must remain rejected.
        for stream, banner, code, failure in (
                ('stderr', '0.6.3 [linux; amd64]\n', 0, None),
                ('stdout', '0.6.3 [linux; amd64]\n', 0, None),
                ('stderr', '0.6.30 [linux; amd64]\n', 0, ValueError),
                ('stderr', '', 0, ValueError),
                ('stderr', '0.6.3 [linux; amd64]\n', 1, subprocess.CalledProcessError)):
            with self.subTest(stream=stream, banner=banner, code=code):
                # Translate only the executable under test; preserve the helper's actual subprocess capture/check options.
                def output(command, **options):
                    self.assertEqual(command, ['/fixture/nimony', '--version'])
                    script = 'import sys; sys.'+stream+'.write('+repr(banner)+'); sys.exit('+str(code)+')'
                    return real_output([sys.executable, '-c', script], **options)
                with patch('setup_nimony.subprocess.check_output', side_effect=output):
                    if failure is None:
                        # The exact banner is retained for CI diagnostics as well as pin validation.
                        self.assertEqual(verify_version(Path('/fixture/nimony'), '0.6.3'), banner)
                    else:
                        # Mismatches and process failures cannot authorize a successful compiler setup.
                        with self.assertRaises(failure):
                            verify_version(Path('/fixture/nimony'), '0.6.3')

    def test_inventory_failure_and_new_module(self):
        """A newly added, otherwise unused source enters the shared graph and cannot bypass its verdict."""
        with temporary_folder() as root:
            (root/'src').mkdir()
            for name in ('a.nim', 'b.nim', 'new.nim', 'ragnarok.nim'):
                (root/'src'/name).write_text('discard\n')
            def check(compiler, source, folder, **options):
                """The graph's failed verdict must dominate a successful peer-main check."""
                if source.name == 'all_sources.nim':
                    text = source.read_text()
                    for path in sorted((root/'src').glob('*.nim')):
                        self.assertIn(str(path), text)
                return dict(source=str(source.relative_to(root)), passed=source.name != 'all_sources.nim')
            with patch.object(modules, 'ROOT', root), patch.object(modules, 'check_module', side_effect=check) as command, patch.object(
                    modules.subprocess, 'check_output', return_value='fixture'), patch('sys.stdout'):
                report = modules.audit(root/'nimony', root/'evidence')
            self.assertEqual(report['status'], 'compile-checks-failed')
            self.assertEqual(command.call_count, 2)
            self.assertEqual([row['source'] for row in report['modules']],
                             ['src/a.nim', 'src/b.nim', 'src/new.nim', 'src/ragnarok.nim'])
            self.assertFalse(any(row['passed'] for row in report['modules']))
            self.assertTrue((root/'evidence/results.json').is_file())

    # A stalled compiler cannot be counted as a pass or silently disappear from the inventory.
    def test_module_timeout_is_failure(self):
        with temporary_folder() as root:
            source = root/'module.nim'
            source.write_text('discard\n')
            with patch.object(modules, 'ROOT', root), patch.object(modules.subprocess, 'run', side_effect=subprocess.TimeoutExpired('compiler', 180)):
                row = modules.check_module(root/'nimony', source, root)
            self.assertFalse(row['passed'])
            self.assertEqual(row['exit_code'], 124)
            self.assertIn('exceeded 180 seconds', (root/row['log']).read_text())

    # The always-run renderer still fails when the preceding runner never produced usable evidence.
    def test_missing_report_cli(self):
        with temporary_folder() as root:
            output = root/'summary.md'
            result = subprocess.run([sys.executable, str(ROOT/'tools/summarize_tests.py'), '--kind', 'runtime',
                                     '--report', str(root/'missing.json'), '--output', str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('No usable verification report', output.read_text())

    # Compilation failure remains visible and explicitly does not claim linked/runtime conformance.
    def test_module_summary_failure(self):
        text = summarize(dict(modules=[dict(source='src/a.nim', passed=True), dict(source='src/b.nim', passed=False)]), 'modules')
        self.assertIn('1/2 modules', text)
        self.assertIn('| `src/b.nim` | Fail |', text)
        self.assertIn('does not establish linking, runtime parity', text)
        with self.assertRaises(ValueError):
            summarize(dict(modules=[]), 'modules')

    # A failed network matrix must remain visible without inflating corpus or contract-guard totals.
    def test_peer_summary_scope(self):
        report = network_report(
                      quic_peer=dict(passed=False, matrix_cases=16, repeated_valid=12))
        text = summarize(report, 'e2e')
        self.assertIn('Authenticated CE 143 peer matrix: Fail', text)
        self.assertIn('Matrix cases: 16; repeated valid startups: 12', text)
        self.assertNotIn('Runtime misuse rejections:', text)
        self.assertNotIn('Independent corpora:', text)

    # Independent lifecycle verdicts must stay visible without counting network waves as compiler or corpus checks.
    def test_retained_summary_scope(self):
        report = network_report(
                      quic_service=dict(passed=True, result=dict(rounds=16, idle=[{}]*16,
                                                               accepted_and_retired_connections=66)),
                      quic_integration_service=dict(passed=False, failure='cancelled owner remained live'))
        text = summarize(report, 'e2e')
        self.assertIn('Retained CE 143 service: Pass', text)
        self.assertIn('Waves: 16; retired connections: 66', text)
        self.assertIn('Integrated digest service: Fail', text)
        self.assertNotIn('Independent corpora:', text)
        self.assertNotIn('Runtime misuse rejections:', text)

    # A failed recovery workload cannot disappear behind healthy reconnect rounds or inflate codec metrics.
    def test_mesh_summary_scope(self):
        report = network_report(
                      quic_mesh=dict(passed=True, result=dict(rounds=16, bidirectional_queries=128)),
                      quic_mesh_disruption=dict(passed=False, failure='pending owners not settled'))
        text = summarize(report, 'e2e')
        self.assertIn('Retained IPv6 mesh: Pass', text)
        self.assertIn('Reconnect rounds: 16; bidirectional queries: 128', text)
        self.assertIn('IPv6 peer-death recovery: Fail', text)
        self.assertNotIn('Runtime misuse rejections:', text)

    # A teardown failure remains distinct from passing retained-engine work and never inflates codec metrics.
    def test_endpoint_soak_summary_scope(self):
        for passed in (False, True):
            # Exercise both verdicts so incomplete evidence cannot be rendered as successful session coverage.
            with self.subTest(passed=passed):
                report = network_report(
                              quic_endpoint_soak=dict(passed=passed, result=dict(rounds=40)))
                text = summarize(report, 'e2e')
                self.assertIn('Same-process endpoint teardown soak: '+('Pass' if passed else 'Fail'), text)
                self.assertEqual('Sessions: 40;' in text, passed)
                self.assertNotIn('Independent corpora:', text)
                self.assertNotIn('Runtime misuse rejections:', text)

    # Passing capacity recovery cannot hide a failed authenticated-close check or inflate compiler metrics.
    def test_admission_summary_scope(self):
        report = network_report(
                      quic_admission=dict(passed=True, result=dict(waves=12, retired_connections=312,
                                                                 healthy_queries_after_release=12)),
                      quic_closed_before_request=dict(passed=False))
        text = summarize(report, 'e2e')
        self.assertIn('Connection/stream admission recovery: Pass', text)
        self.assertIn('Waves: 12; retired connections: 312; healthy queries after release: 12', text)
        self.assertIn('Authenticated connection loss before request: Fail', text)
        self.assertNotIn('Runtime misuse rejections:', text)
        # Exercise the inverse outcomes as well; successful close detection must retain its zero-stream observation.
        report['quic_admission'] = dict(passed=False)
        report['quic_closed_before_request'] = dict(passed=True, result=dict(application_streams=0, closed_seconds=2.0))
        text = summarize(report, 'e2e')
        self.assertIn('Connection/stream admission recovery: Fail', text)
        self.assertIn('Application streams: 0; close detection seconds: 2.0', text)

    # A worker lifecycle failure cannot hide behind passing networking or inflate codec/compiler totals.
    def test_offload_summary_scope(self):
        for passed in (False, True):
            # Both verdicts must remain visible, and counts belong only to a completed workload.
            with self.subTest(passed=passed):
                report = network_report(
                              quic_offload=dict(passed=passed, result=dict(rounds=10, workers=2, job_cap=4,
                                                                          verified_jobs=30, healthy_light_queries=70)))
                text = summarize(report, 'e2e')
                self.assertIn('Bounded proof offload: '+('Pass' if passed else 'Fail'), text)
                self.assertEqual('workers: 2; job cap: 4' in text, passed)
                self.assertNotIn('Independent corpora:', text)
                self.assertNotIn('Runtime misuse rejections:', text)

    # Unit summaries cannot claim another job's runtime or compiler evidence.
    def test_slice_summary_scope(self):
        report = dict(status='checks-passed', suites=[dict(passed=True)], runtime=[dict(passed=True)],
                      fields=[dict(passed=True), dict(passed=True)], privacy=[dict(passed=True)], nominal=[], schemas=[], contracts=[dict(passed=True)],
                      ownership_compile=[dict(passed=True)], example_corpus=dict(passed=False, requests=3))
        text = summarize(report, 'runtime')
        self.assertNotIn('Runtime misuse rejections:', text)
        self.assertNotIn('Compilation rejections:', text)
        self.assertIn('partial evidence', text)
        self.assertIn('| `example_corpus` | Fail | 3 |', text)
        with self.assertRaises(KeyError):
            summarize({}, 'runtime')


# Imports expose inert test helpers without downloading tools or starting compilation.
if __name__ == '__main__':
    unittest.main(verbosity=2)


class StorageResourceCISafeguards(unittest.TestCase):
    """All resource panels stay beside the existing speed panel in one opt-in Perf Storage job."""

    def test_resource_panels_and_artifacts_remain_grouped(self):
        """Resource panels remain with the ordinary comparison after sustained growth moves out."""
        text=(ROOT/'.github/workflows/ci.yml').read_text(); section=family_section(text, 'perf', 'bench-storage')
        self.assertEqual(section.count('run: make bench-storage\n'),1)
        self.assertIn('run: make bench-storage-resources bench-storage-allocations bench-storage-lifetimes bench-storage-deployment bench-storage-fresh-reopen bench-storage-file-cache',section)
        self.assertIn('summary-storage-resources SUMMARY_OUTPUT="$GITHUB_STEP_SUMMARY"',section)
        for name in ('storage-resources','storage-allocations','storage-lifetimes','storage-deployment','storage-fresh-reopen','storage-file-cache'):
            self.assertIn('build/tests/'+name+'/results.json',section)
            self.assertIn('build/tests/'+name+'/*.log',section)
