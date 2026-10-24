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
        self.assertIn('type: choice\n        options: [smoke, unit, e2e, build, docker, interop, perf, ref-pvm, fuzz, fuzz-pvm, bench-pvm, compare-pvm, bench-storage, bench-storage-growth, full]\n        default: full', triggers)
        self.assertNotIn('pull_request_target', triggers)
        for target in ('check-models', 'check-python', 'check-modules', 'check-unit', 'check-failures', 'check-guards', 'check-e2e',
                       'check-telemetry-interop-ci', 'check-pvm-reference'):
            # Every group runs once and independently; no omnibus duplicate or serial CI dependency chain.
            self.assertEqual(text.count('run: make '+target+'\n'), 1)
        self.assertEqual(text.count('needs:'), 8)
        self.assertIn('needs: unit', text)
        self.assertNotIn('run: make check\n', text)
        self.assertNotIn('mkdir', text)
        self.assertNotIn('nimony-trial', text)
        self.assertNotIn('tools/setup_nimony.py', text)
        self.assertNotIn('cargo fetch', text)

    def test_pr_updates_request_only_smoke_with_isolated_concurrency(self):
        """An ordinary PR update runs the small gate without requesting or cancelling heavy CI."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = family_section(text, 'compile', 'smoke')
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

    # The lightweight gate must roll up without starting heavy compilation on ordinary PR updates.
    def test_smoke_compile_rollup(self):
        """A lightweight request expands only Smoke and still requires the complete selected matrix."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        gate = job_section(text, 'compile-status')
        self.assertIn('needs: compile', gate)
        self.assertIn('SHARDS_RESULT: ${{ needs.compile.result }}', gate)
        families = selected_families(text, 'compile', event_context('pull_request', 'synchronize'))
        self.assertEqual([row['group'] for row in families], ['smoke'])
        self.assertNotIn('minutes', families[0])

    def test_every_job_uses_shared_timeout(self):
        """Randomized workload variance has one 60-minute safety limit across all CI jobs."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        jobs = re.findall(r'^  ([\w-]+):\n', text.split('jobs:\n', 1)[1], re.MULTILINE)
        self.assertEqual(text.count('&ci-job-timeout 60'), 1)
        for job in jobs:
            # Aggregate and future jobs must opt into the same bound rather than inherit six hours.
            section = job_section(text, job)
            expected = '&ci-job-timeout 60' if job == 'compile' else '*ci-job-timeout'
            self.assertIn('timeout-minutes: '+expected+'\n', section)
            self.assertEqual(section.count('    timeout-minutes:'), 1)
            self.assertNotIn('"minutes":', section)

    # Scope guards must act on the label addition, never on persistent PR labels or a branch name.
    def test_ci_request_scopes(self):
        """Actual matrix expressions preserve every automatic, labeled and standalone manual request."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        groups = {'compile': ['smoke', 'modules', 'python', 'guards'],
                  'interop': ['pvm-reference', 'telemetry-interop'],
                  'perf': ['bench-pvm', 'bench-storage', 'bench-storage-growth'],
                  'build': ['docker', 'binary', 'binary']}
        for event in (event_context(), event_context('workflow_dispatch', suite='full'),
                      event_context('pull_request', 'labeled', 'ci:full')):
            # Full requests include every family, with both native binary hosts retained.
            for job, wanted in groups.items():
                self.assertEqual([row['group'] for row in selected_families(text, job, event)], wanted)
        for action in ('opened', 'reopened', 'synchronize'):
            # An ordinary PR update runs Smoke alone, irrespective of persistent heavy labels.
            event = event_context('pull_request', action)
            for job in groups:
                self.assertEqual([row['group'] for row in selected_families(text, job, event)],
                                 ['smoke'] if job == 'compile' else [])
        for label, active in [('ci:unit', ['compile']), ('ci:interop', ['interop']),
                              ('ci:perf', ['perf']), ('ci:e2e', []), ('ci:fuzz', []), ('unrelated', [])]:
            # A label addition selects exactly its group; unrelated labels schedule no matrix members.
            for job in groups:
                self.assertEqual([row['group'] for row in selected_families(
                    text, job, event_context('pull_request', 'labeled', label))],
                    groups[job] if job in active else [])
        manual = {'smoke': ('compile', ['smoke']), 'unit': ('compile', groups['compile']),
                  'interop': ('interop', groups['interop']), 'ref-pvm': ('interop', ['pvm-reference']),
                  'perf': ('perf', groups['perf']), 'bench-pvm': ('perf', ['bench-pvm']),
                  'bench-storage': ('perf', ['bench-storage']),
                  'bench-storage-growth': ('perf', ['bench-storage-growth']),
                  'build': ('build', groups['build']), 'docker': ('build', ['docker']),
                  'e2e': ('', []), 'fuzz': ('', []), 'fuzz-pvm': ('', [])}
        for suite, (owner, wanted) in manual.items():
            # Standalone requests never claim sibling coverage or launch another group's work.
            for job in groups:
                self.assertEqual([row['group'] for row in selected_families(
                    text, job, event_context('workflow_dispatch', suite=suite))], wanted if job == owner else [])
        self.assertNotIn('github.event.pull_request.labels', text)

    def test_paired_pvm_is_explicit_and_uses_exact_endpoints(self):
        """Only the requested revision experiment runs, with literal refs and a separate control output."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        condition = job_condition(text, 'compare-pvm')
        for event, expected in [
                (event_context(), False),
                (event_context('workflow_dispatch', suite='compare-pvm'), True),
                (event_context('workflow_dispatch', suite='perf'), False),
                (event_context('workflow_dispatch', suite='full'), False),
                (event_context('pull_request', 'labeled', 'ci:pvm-compare'), True),
                (event_context('pull_request', 'synchronize', 'ci:pvm-compare'), False),
                (event_context('pull_request', 'labeled', 'ci:perf'), False),
                (event_context('pull_request', 'labeled', 'ci:full'), False),
                (event_context('pull_request', 'labeled', 'ci:pvm-compare', state='closed'), False)]:
            # Persistent labels and closed PRs cannot launch another expensive comparison.
            self.assertEqual(bool(expression(condition, event)), expected)
        section = job_section(text, 'compare-pvm')
        self.assertIn('timeout-minutes: *ci-job-timeout', section)
        self.assertIn('runs-on: ubuntu-24.04', section)
        self.assertIn('fetch-depth: 0', section)
        self.assertIn('persist-credentials: false', section)
        self.assertIn('ref: ${{ github.event.pull_request.head.sha || github.sha }}', section)
        self.assertIn("PVM_COMPARE_BASE: ${{ github.event.pull_request.base.sha || inputs.pvm_compare_base || 'HEAD^' }}", section)
        baseline = section.index('run: make compare-pvm-guests\n')
        control = section.index('run: make compare-pvm-guests PVM_COMPARE_BASE=HEAD PVM_COMPARE_OUTPUT=build/tests/pvm-guest-control')
        reference = section.index('run: make bench-pvm-guests\n')
        self.assertLess(baseline, control)
        self.assertLess(control, reference)
        self.assertNotIn('continue-on-error', section)
        self.assertNotIn('needs:', section)
        self.assertEqual(section.count('if: always()'), 2)
        for folder in ('pvm-guest-compare', 'pvm-guest-control', 'pvm-guests'):
            # Both summaries and raw failed/partial evidence survive without uploading build trees.
            self.assertIn('build/tests/'+folder+'/summary.md', section)
            self.assertIn('build/tests/'+folder+'/*.json', section)
        self.assertNotIn('/snapshots/', section)
        self.assertNotIn('/compiler-', section)

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
            for label in ('ci:full', 'ci:unit', 'ci:e2e', 'ci:interop', 'ci:perf', 'ci:fuzz', 'ci:pvm-compare', 'unrelated'):
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
        expected = ("ci-${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.event.pull_request.state != 'open' && github.run_id || github.event_name == 'pull_request' && github.event.pull_request.state == 'open' && github.event.action != 'labeled' && format('smoke-{0}', github.event.pull_request.number) || github.event_name == 'pull_request' && github.event.pull_request.state == 'open' && "
                    "github.event.label.name != 'ci:unit' && github.event.label.name != 'ci:full' && "
                    "github.event.label.name != 'ci:e2e' && github.event.label.name != 'ci:interop' && github.event.label.name != 'ci:perf' && github.event.label.name != 'ci:fuzz' && github.event.label.name != 'ci:pvm-compare' && github.run_id || github.ref }}")
        self.assertIn('group: '+expected+'\n  cancel-in-progress: true', text)

    # The matrix covers every partition once, and the stable unit gate rejects every non-success result.
    def test_ci_unit_partition_gate(self):
        from native_tests import parse_unit_shard
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        values = json.loads('['+re.search(r'        shard: \[([^\n]+)\]', text).group(1)+']')
        partitions = [parse_unit_shard(value) for value in values]
        count = partitions[0][1]
        self.assertEqual(count, 16)
        self.assertEqual(partitions, [(index, count) for index in range(1, count+1)])
        unit = text.split('  unit:\n', 1)[1].split('  unit-status:\n', 1)[0]
        self.assertIn('CI_SHARD_SEED: ${{ github.run_id }}', unit)
        gate = text.split('  unit-status:\n', 1)[1].split('  failures:\n', 1)[0]
        self.assertIn('name: Unit', gate)
        self.assertIn('needs: unit', gate)
        self.assertIn('if: ${{ always() && (', gate)
        self.assertIn('SHARDS_RESULT: ${{ needs.unit.result }}', gate)
        command = re.search(r'        run: ([^\n]+)', gate).group(1)
        for result in ['success', 'failure', 'cancelled', 'skipped']:
            # Exercise the actual aggregate command so a skipped/failed matrix cannot become green.
            with self.subTest(result=result):
                status = subprocess.run(['bash', '-c', command], env={'SHARDS_RESULT': result}).returncode
                self.assertEqual(status == 0, result == 'success')

    # Every contract partition is scheduled, and its stable aggregate rejects failure, cancellation and skip.
    def test_ci_contract_partition_gate(self):
        from failure_plans import parse_failure_shard
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = text.split('  failures:\n', 1)[1].split('  failures-status:\n', 1)[0]
        values = json.loads('['+re.search(r'        shard: \[([^\n]+)\]', section).group(1)+']')
        partitions = [parse_failure_shard(value) for value in values]
        count = partitions[0][1]
        self.assertEqual(count, 6)
        self.assertEqual(partitions, [(index, count) for index in range(1, count+1)])
        self.assertIn('FAILURE_SHARD: ${{ matrix.shard }}', section)
        self.assertIn('CI_SHARD_SEED: ${{ github.run_id }}', section)
        gate = text.split('  failures-status:\n', 1)[1].split('  e2e:\n', 1)[0]
        self.assertIn('name: Contract', gate)
        self.assertIn('needs: failures', gate)
        self.assertIn('if: ${{ always() && (', gate)
        self.assertIn('SHARDS_RESULT: ${{ needs.failures.result }}', gate)
        command = re.search(r'        run: ([^\n]+)', gate).group(1)
        for result in ['success', 'failure', 'cancelled', 'skipped']:
            # Execute the actual gate command rather than inferring success from job presence.
            with self.subTest(result=result):
                status = subprocess.run(['bash', '-c', command], env={'SHARDS_RESULT': result}).returncode
                self.assertEqual(status == 0, result == 'success')

    def test_ci_e2e_family_gate(self):
        """Every declared E2E family runs independently and the stable gate refuses incomplete matrices."""
        from e2e_checks import PLAN
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = text.split('  e2e:\n', 1)[1].split('  e2e-status:\n', 1)[0]
        groups = re.findall(r'group: ([a-z_]+), name:', section)
        self.assertEqual(tuple(groups), PLAN.groups())
        self.assertIn('fail-fast: false', section)
        self.assertIn('E2E_GROUP: ${{ matrix.family.group }}', section)
        self.assertIn('name: E2E / ${{ matrix.family.name }}', section)
        self.assertIn('name: ${{ matrix.os }}-e2e-${{ matrix.family.group }}-${{ github.run_attempt }}', section)
        self.assertNotIn('needs:', section)
        gate = text.split('  e2e-status:\n', 1)[1].split('  interop:\n', 1)[0]
        self.assertIn('name: E2E', gate)
        self.assertIn('needs: e2e', gate)
        self.assertIn('SHARDS_RESULT: ${{ needs.e2e.result }}', gate)
        command = re.search(r'        run: ([^\n]+)', gate).group(1)
        for result in ('success', 'failure', 'cancelled', 'skipped'):
            # Exercise the exact shell predicate rather than relying on matrix job names alone.
            with self.subTest(result=result):
                code = subprocess.run(['bash', '-c', command], env={'SHARDS_RESULT': result}).returncode
                self.assertEqual(code == 0, result == 'success')

    def test_group_gates_require_every_dependency(self):
        """Failed, skipped or cancelled matrix results cannot produce green group aggregates."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        for group in ('compile', 'interop', 'perf', 'build'):
            gate = job_section(text, group+'-status')
            self.assertIn('needs: '+group+'\n', gate)
            self.assertIn('if: ${{ always() && (', gate)
            self.assertIn('SHARDS_RESULT: ${{ needs.'+group+'.result }}', gate)
            command = re.search(r'        run: ([^\n]+)', gate).group(1)
            for result in ('success', 'failure', 'cancelled', 'skipped'):
                status = subprocess.run(['bash', '-c', command], env={'SHARDS_RESULT': result}).returncode
                self.assertEqual(status == 0, result == 'success')
            for suite in ('smoke', 'ref-pvm', 'bench-pvm', 'bench-storage', 'bench-storage-growth', 'docker'):
                # Only Compile's lightweight requests have an aggregate; standalone other groups omit theirs.
                condition = re.search(r'^    if: (.+)$', gate, re.MULTILINE).group(1)
                self.assertEqual(bool(expression(condition, event_context('workflow_dispatch', suite=suite))),
                                 group == 'compile' and suite == 'smoke')
        fuzz = job_section(text, 'fuzz-status')
        self.assertIn('needs: [pvm-fuzz]', fuzz)
        command = re.search(r'        run: ([^\n]+)', fuzz).group(1)
        for result in ('success', 'failure', 'cancelled', 'skipped'):
            status = subprocess.run(['bash', '-c', command], env={'PVM_FUZZ_RESULT': result}).returncode
            self.assertEqual(status == 0, result == 'success')

    def test_binary_builds_match_pinned_hosts_and_publish_only_archives(self):
        """The combined Build matrix keeps Docker and both supported native archive hosts distinct."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = family_section(text, 'build', 'binary', 'Linux')
        rows = selected_families(text, 'build', event_context())
        binary = [row for row in rows if row['group'] == 'binary']
        pins = json.loads((ROOT/'spec/toolchain.json').read_text())
        self.assertEqual({row['platform'] for row in binary}, {name.replace('_', '-') for name in pins['platforms']})
        self.assertEqual([(row['name'], row['os']) for row in rows],
                         [('Docker', 'ubuntu-latest'), ('Linux', 'ubuntu-24.04'), ('macOS', 'macos-15')])
        self.assertIn('fail-fast: false', section)
        self.assertIn('name: Build / ${{ matrix.family.name }}', section)
        self.assertIn('run: make package-binary', section)
        self.assertNotIn('run: make check-docker', section)
        self.assertIn('if-no-files-found: error', section)
        self.assertIn('build/dist/ragnarok-${{ matrix.family.platform }}.tar.gz.sha256', section)
        self.assertNotIn('contents: write', text)
        self.assertNotIn('needs:', section)
        make = (ROOT/'Makefile').read_text()
        self.assertIn('package-binary: export BINARY_PACKAGE = 1', make)
        self.assertIn('package-binary: build\n\t$(PYTHON) tools/package_binary.py', make)
        self.assertIn('if [ "$(BINARY_PACKAGE)" = 1 ]; then packages="$$packages patchelf"; fi;', make)

    # Every independent CI job must visibly reject incomplete inventories before provisioning its workload.
    def test_ci_inventory_preflight(self):
        """Every native matrix family validates inventory before its own provisioning command."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        self.assertIn('run: &inventory-run make check-inventory', text)
        for job, family, target in [('compile', 'modules', 'check-modules'), ('compile', 'python', 'check-python'),
                                    ('compile', 'guards', 'check-guards'), ('interop', 'pvm-reference', 'check-pvm-reference'),
                                    ('interop', 'telemetry-interop', 'check-telemetry-interop-ci'),
                                    ('perf', 'bench-pvm', 'bench-pvm'), ('perf', 'bench-storage', 'bench-storage'),
                                    ('perf', 'bench-storage-growth', 'bench-storage-growth'), ('build', 'docker', 'check-docker')]:
            section = family_section(text, job, family)
            self.assertEqual(section.count('name: Validate verification inventory'), 1)
            self.assertLess(section.index('name: Validate verification inventory'), section.index('run: make '+target))
        for job in ('unit', 'failures', 'e2e', 'pvm-fuzz', 'models'):
            self.assertIn('run: *inventory-run', job_section(text, job))
        self.assertNotIn('continue-on-error:', text)

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
        section = family_section(text, 'perf', 'bench-pvm')
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
        for group, names in [('compile', ['Smoke', 'Source', 'Reference & Tooling', 'Rejection Guards']),
                             ('interop', ['PVM', 'Telemetry']), ('perf', ['PVM', 'Storage', 'Storage Growth']),
                             ('build', ['Docker', 'Linux', 'macOS'])]:
            self.assertEqual([row['name'] for row in selected_families(text, group, event_context())], names)
            self.assertIn('name: '+group.title()+' / ${{ matrix.family.name }}', job_section(text, group))
            self.assertEqual(text.count('    name: '+group.title()+' / ${{ matrix.family.name }}'), 1)
        for removed in ('smoke', 'modules', 'python', 'guards', 'pvm-reference', 'telemetry-interop',
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

    def test_storage_growth_is_an_independent_perf_family(self):
        """Growth preserves dispatch/group triggers, strict failure and artifacts without serial dependencies."""
        text=(ROOT/'.github/workflows/ci.yml').read_text()
        short=family_section(text, 'perf', 'bench-storage')
        growth=family_section(text, 'perf', 'bench-storage-growth')
        self.assertIn('name: Perf / ${{ matrix.family.name }}',growth)
        self.assertIn('Storage Growth',growth)
        for trigger in ("github.event_name == 'push'", "inputs.suite == 'perf'", "inputs.suite == 'bench-storage-growth'",
                        "inputs.suite == 'full'", "github.event.label.name == 'ci:perf'", "github.event.label.name == 'ci:full'"):
            # An explicit short-only dispatch remains short-only; group requests still execute both jobs.
            self.assertIn(trigger,growth)
        self.assertEqual(growth.count('run: make bench-storage-growth\n'),1)
        self.assertIn('summary-storage-growth SUMMARY_OUTPUT="$GITHUB_STEP_SUMMARY"',growth)
        self.assertIn('timeout-minutes: *ci-job-timeout',growth)
        self.assertIn('always()',growth)
        self.assertIn('name: bench-storage-growth-${{ github.run_attempt }}',growth)
        for name in ('results.json','summary.md','growth/results.json','growth/samples.csv',
                     'growth/publications.csv','growth/io/*.log','growth/io/results.json','growth/io/calls.csv'):
            self.assertIn('build/tests/storage-growth-benchmark/'+name,growth)
        for section in (short,growth):
            # A failed panel remains a failure and independent runners cannot serialize each other.
            self.assertNotIn('needs:',section)
            self.assertNotIn('continue-on-error',section)
        self.assertNotIn('/growth/',short)

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
        for system, machine, name in (('Linux', 'x86_64', 'linux_amd64'), ('Darwin', 'arm64', 'macos_arm64')):
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
            self.assertEqual(runner.return_value.command.call_args.kwargs['timeout'], 900)
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
