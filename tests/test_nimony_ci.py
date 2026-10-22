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
        # PR labels are the only PR trigger; opening, pushing and rebasing cannot request runners.
        triggers = text.split('"on":\n', 1)[1].split('\npermissions:', 1)[0]
        self.assertIn('push:\n    branches: [master]\n', triggers)
        self.assertIn('pull_request:\n    types: [labeled]\n', triggers)
        self.assertIn('workflow_dispatch:\n    inputs:\n      suite:', triggers)
        self.assertIn('type: choice\n        options: [unit, e2e, docker, interop, perf, pvm-reference, bench-pvm, bench-storage, full]\n        default: full', triggers)
        self.assertNotIn('pull_request_target', triggers)
        self.assertNotIn('synchronize', triggers)
        self.assertNotIn('opened', triggers)
        for target in ('check-models', 'check-python', 'check-modules', 'check-unit', 'check-failures', 'check-guards', 'check-e2e',
                       'check-telemetry-interop-ci', 'check-pvm-reference'):
            # Every group runs once and independently; no omnibus duplicate or serial CI dependency chain.
            self.assertEqual(text.count('run: make '+target+'\n'), 1)
        self.assertEqual(text.count('needs:'), 2)
        self.assertIn('needs: unit', text)
        self.assertNotIn('run: make check\n', text)
        self.assertNotIn('mkdir', text)
        self.assertNotIn('nimony-trial', text)
        self.assertNotIn('tools/setup_nimony.py', text)
        self.assertNotIn('cargo fetch', text)

    # Scope guards must act on the label addition, never on persistent PR labels or a branch name.
    def test_ci_request_scopes(self):
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        requested = ("github.event_name == 'push' || (github.event_name == 'workflow_dispatch' && "
                     "(inputs.suite == 'unit' || inputs.suite == 'full')) || "
                     "(github.event_name == 'pull_request' && (github.event.label.name == 'ci:unit' || "
                     "github.event.label.name == 'ci:full'))")
        full = ("github.event_name == 'push' || (github.event_name == 'workflow_dispatch' && "
                "inputs.suite == 'full') || (github.event_name == 'pull_request' && "
                "github.event.label.name == 'ci:full')")
        e2e = ("github.event_name == 'push' || (github.event_name == 'workflow_dispatch' && "
               "(inputs.suite == 'e2e' || inputs.suite == 'full')) || "
               "(github.event_name == 'pull_request' && (github.event.label.name == 'ci:e2e' || "
               "github.event.label.name == 'ci:full'))")
        self.assertIn('if: &requested ${{ '+requested+' }}', text)
        self.assertIn('if: &full ${{ '+full+' }}', text)
        for job, condition in [('modules', '&requested ${{ '+requested+' }}'),
                               ('python', '*requested'), ('models', '*requested'), ('unit', '*requested'),
                               ('docker', '${{ '+requested.replace("inputs.suite == 'unit' ||",
                                   "inputs.suite == 'unit' || inputs.suite == 'docker' ||")+' }}'),
                               ('guards', '&full ${{ '+full+' }}'), ('failures', '*full'),
                               ('pvm-reference', '${{ '+full.replace("inputs.suite == 'full')",
                                   "(inputs.suite == 'interop' || inputs.suite == 'pvm-reference' || inputs.suite == 'full'))").replace("github.event.label.name == 'ci:full')",
                                   "(github.event.label.name == 'ci:interop' || github.event.label.name == 'ci:full'))")+' }}'),
                               ('e2e', '${{ '+e2e+' }}'),
                               ('telemetry-interop', '${{ '+full.replace("inputs.suite == 'full')",
                                   "(inputs.suite == 'interop' || inputs.suite == 'full'))").replace("github.event.label.name == 'ci:full')",
                                   "(github.event.label.name == 'ci:interop' || github.event.label.name == 'ci:full'))")+' }}'),
                               ('unit-status', '${{ always() && ('+requested+') }}'),
                               ('failures-status', '${{ always() && ('+full+') }}')]:
            # Gates retain the same selection as their matrix while still observing failed/cancelled jobs.
            with self.subTest(job=job):
                section = re.search(r'^  '+job+r':\n(.*?)(?=^  [\w-]+:|\Z)',
                                    text, re.MULTILINE | re.DOTALL).group(1)
                actual = re.search(r'^    if: (.+)$', section, re.MULTILINE).group(1)
                self.assertEqual(actual, condition)
        self.assertNotIn('github.event.pull_request.labels', text)
        self.assertIn('persist-credentials: false', text)
        self.assertIn('permissions:\n  contents: read', text)

    # Ignored labels cannot replace/cancel a pending requested run; selected requests share one PR group.
    def test_ci_request_concurrency(self):
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        expected = ("ci-${{ github.workflow }}-${{ github.event_name == 'pull_request' && "
                    "github.event.label.name != 'ci:unit' && github.event.label.name != 'ci:full' && "
                    "github.event.label.name != 'ci:e2e' && github.event.label.name != 'ci:interop' && github.event.label.name != 'ci:perf' && github.run_id || github.ref }}")
        self.assertIn('group: '+expected+'\n  cancel-in-progress: true', text)

    # The matrix covers every partition once, and the stable unit gate rejects every non-success result.
    def test_ci_unit_partition_gate(self):
        from native_tests import parse_unit_shard
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        values = json.loads('['+re.search(r'        shard: \[([^\n]+)\]', text).group(1)+']')
        partitions = [parse_unit_shard(value) for value in values]
        count = partitions[0][1]
        self.assertEqual(partitions, [(index, count) for index in range(1, count+1)])
        gate = text.split('  unit-status:\n', 1)[1].split('  failures:\n', 1)[0]
        self.assertIn('name: Native unit and codec tests', gate)
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
        self.assertEqual(partitions, [(index, count) for index in range(1, count+1)])
        self.assertIn('FAILURE_SHARD: ${{ matrix.shard }}', section)
        gate = text.split('  failures-status:\n', 1)[1].split('  e2e:\n', 1)[0]
        self.assertIn('name: Runtime failure and contract tests', gate)
        self.assertIn('needs: failures', gate)
        self.assertIn('if: ${{ always() && (', gate)
        self.assertIn('SHARDS_RESULT: ${{ needs.failures.result }}', gate)
        command = re.search(r'        run: ([^\n]+)', gate).group(1)
        for result in ['success', 'failure', 'cancelled', 'skipped']:
            # Execute the actual gate command rather than inferring success from job presence.
            with self.subTest(result=result):
                status = subprocess.run(['bash', '-c', command], env={'SHARDS_RESULT': result}).returncode
                self.assertEqual(status == 0, result == 'success')

    # Every independent CI job must visibly reject incomplete inventories before provisioning its workload.
    def test_ci_inventory_preflight(self):
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        definition = text.split('      - &inventory\n', 1)[1].split('      - ', 1)[0]
        self.assertEqual(definition.strip(),
                         'name: Validate verification inventory\n        run: make check-inventory')
        jobs = ('modules', 'python', 'guards', 'unit', 'failures', 'e2e', 'telemetry-interop', 'docker', 'pvm-reference')
        for job in (*jobs, 'bench-pvm', 'bench-storage'):
            # Exact job boundaries keep an appended independent workload from entering its neighbor's scope.
            with self.subTest(job=job):
                section = re.search(r'^  '+job+r':\n(.*?)(?=^  [\w-]+:|\Z)',
                                    text, re.MULTILINE | re.DOTALL).group(1)
                preflight = '- &inventory' if job == 'modules' else '- *inventory'
                target = job if job.startswith('bench-') else 'check-'+job
                self.assertEqual(section.count(preflight), 1)
                self.assertLess(section.index(preflight), section.index('run: make '+target))
        self.assertNotIn('continue-on-error:', text)

    def test_pvm_reference_evidence_scope(self):
        """The separate full-scope job keeps failed-run evidence without silently allowing failure."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = re.search(r'^  pvm-reference:\n(.*?)(?=^  [\w-]+:|\Z)', text, re.MULTILINE | re.DOTALL).group(1)
        self.assertIn('runs-on: ubuntu-latest', section)
        self.assertIn('RAGNAROK_PVM_REFERENCE_BACKEND: interpreter', section)
        self.assertNotIn('sysctl', section)
        self.assertIn("inputs.suite == 'interop'", section)
        self.assertIn("github.event.label.name == 'ci:interop'", section)
        self.assertEqual(section.count('run: make check-pvm-reference'), 1)
        self.assertIn('if: always()\n        uses: *upload-artifact', section)
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
        section = text.split('  bench-pvm:\n', 1)[1]
        self.assertIn("if: ${{ github.event_name == 'push' || (github.event_name == 'workflow_dispatch' && (inputs.suite == 'perf' || inputs.suite == 'bench-pvm' || inputs.suite == 'full')) || (github.event_name == 'pull_request' && (github.event.label.name == 'ci:perf' || github.event.label.name == 'ci:full')) }}", section)
        self.assertEqual(section.count('run: make bench-pvm\n'), 1)
        self.assertLess(section.index('- *inventory'), section.index('run: make bench-pvm'))
        self.assertIn('summary-pvm-benchmark SUMMARY_OUTPUT="$GITHUB_STEP_SUMMARY"', section)
        for name in ('results.json','samples.csv','summary.md'):
            self.assertIn('build/tests/pvm-benchmark/'+name, section)
        self.assertNotIn('continue-on-error', section)
        self.assertNotIn('sysctl', section)

    # Interop jobs remain adjacent in the workflow and use consistent group names in Actions.
    def test_interop_and_perf_job_names(self):
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        jobs = re.findall(r'^  ([\w-]+):\n    if:', text, re.MULTILINE)
        index = jobs.index('pvm-reference')
        self.assertEqual(jobs[index:index+2], ['pvm-reference', 'telemetry-interop'])
        self.assertIn('name: Interop PVM', text)
        self.assertIn('name: Interop JAM Tart', text)
        self.assertIn('name: Perf PVM', text)
        self.assertIn('name: Perf Storage', text)
        index = jobs.index('bench-pvm')
        self.assertEqual(jobs[index:index+2], ['bench-pvm', 'bench-storage'])

    def test_storage_perf_scope_and_summary(self):
        """Storage shares the Perf group while retaining independent validated artifacts and failure status."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = text.split('  bench-storage:\n', 1)[1]
        for trigger in ("github.event_name == 'push'", "inputs.suite == 'perf'", "inputs.suite == 'bench-storage'",
                        "inputs.suite == 'full'", "github.event.label.name == 'ci:perf'", "github.event.label.name == 'ci:full'"):
            self.assertIn(trigger, section)
        self.assertEqual(section.count('run: make bench-storage\n'), 1)
        self.assertIn('summary-storage-benchmark SUMMARY_OUTPUT="$GITHUB_STEP_SUMMARY"', section)
        self.assertIn('if: always()', section)
        for name in ('results.json', 'samples.csv', 'summary.md'):
            self.assertIn('build/tests/storage-benchmark/'+name, section)
        self.assertNotIn('continue-on-error', section)
        self.assertNotIn('needs:', section)

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

    # Inventory discovery must include a newly added module and keep a failed module red while checking later files.
    def test_inventory_failure_and_new_module(self):
        with temporary_folder() as root:
            (root/'src').mkdir()
            # The third file represents new code that must not rely on a manually updated allowlist.
            for name in ('a.nim', 'b.nim', 'new.nim'):
                (root/'src'/name).write_text('discard\n')
            ready = threading.Barrier(2)
            # Require overlapping checks while retaining one genuine failure and a later new source.
            def check(compiler, source, folder):
                if source.name != 'new.nim':
                    # The first two modules must overlap without depending on host scheduling speed.
                    ready.wait(timeout=5)
                return dict(source=str(source.relative_to(root)), passed=source.name != 'b.nim')
            with patch.dict('os.environ', {'COMPILE_CHECK_JOBS': '2'}), patch.object(modules, 'ROOT', root), patch.object(modules, 'check_module', side_effect=check), patch.object(modules.subprocess, 'check_output', return_value='fixture'), patch('sys.stdout', new=io.StringIO()):
                report = modules.audit(root/'nimony', root/'evidence')
            self.assertEqual(report['status'], 'compile-checks-failed')
            self.assertEqual(report['jobs'], 2)
            self.assertEqual(len(report['modules']), 3)
            self.assertEqual([row['source'] for row in report['modules']], ['src/a.nim', 'src/b.nim', 'src/new.nim'])
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
