# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject incomplete revision comparisons, stale aggregates and changed snapshot identities."""
import copy
import json
import os
import subprocess
import sys
import native_checks
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import pvm_guest_compare as compare
import pvm_guest_inputs as inputs
from pvm_guest_inputs import CASES, preparation_identity, validate_cases


def complete_report():
    """Construct complete paired observations independently, with real parser-compatible policy metadata."""
    report = dict(status='checks-passed', cases=[dict(guest=g, limit=n) for g, n in CASES], runs=[])
    for repeat, order in enumerate((('baseline', 'candidate'), ('candidate', 'baseline'))):
        for guest, limit in CASES:
            for mode in compare.MODES:
                for variant in order:
                    preparation = None
                    if mode == 'planned':
                        preparation = dict(cpu_ns=1, wall_ns=1, code_bytes=2, block_count=1,
                                           payload_bytes=16, cycle_limit=1000000)
                    elif mode == 'memo':
                        preparation = dict(cpu_ns=0, wall_ns=1, code_bytes=2, payload_bytes=16,
                                           cycle_limit=1000000, priced_blocks=1)
                    samples = [dict(sample=i, cpu_ns=100 if variant == 'baseline' else 110,
                                    wall_ns=120) for i in range(13)]
                    report['runs'].append(dict(variant=variant, guest=guest, limit=limit,
                        mode=mode, pass_index=repeat, parsed=dict(guest=guest,
                            samples=samples, preparation=preparation)))
    return report


class GuestComparisonTests(unittest.TestCase):
    """One observed success must cover the exact matrix, modes, process orders and byte identities."""

    def test_cli_keeps_control_evidence_separate(self):
        """CI can select a private output directory without changing scope or interpolating a baseline ref."""
        with patch.dict(compare.os.environ, {'RAGNAROK_PVM_COMPARE_BASE': 'literal;ref',
                'RAGNAROK_PVM_COMPARE_SCOPE': '',
                'RAGNAROK_PVM_COMPARE_SYNTHETIC': '',
                'RAGNAROK_PVM_COMPARE_OUTPUT': 'build/tests/pvm-guest-control'}), patch.object(compare, 'run') as run:
            compare.main()
        run.assert_called_once_with('literal;ref', scope='all', folder='build/tests/pvm-guest-control', synthetic=False)
        with patch.dict(compare.os.environ, {'RAGNAROK_PVM_COMPARE_BASE': 'HEAD',
                'RAGNAROK_PVM_COMPARE_SCOPE': 'controls',
                'RAGNAROK_PVM_COMPARE_SYNTHETIC': '0',
                'RAGNAROK_PVM_COMPARE_OUTPUT': ''}), patch.object(compare, 'run') as run:
            compare.main()
        run.assert_called_once_with('HEAD', scope='controls', folder=None, synthetic=False)

    def test_make_exports_comparison_settings_literally(self):
        """A workflow baseline ref containing Make syntax must reach Git as data rather than execute it."""
        makefile = (compare.ROOT/'Makefile').read_text()
        exports = [line for line in makefile.splitlines()
                   if line.startswith('compare-pvm-guests: export RAGNAROK_PVM_COMPARE_')]
        self.assertEqual(len(exports), 4)
        names = ('BASE', 'SCOPE', 'OUTPUT', 'SYNTHETIC')
        values = {name: 'literal-$(shell echo expanded)-'+name for name in names}
        probe = "import os,json; print(json.dumps({n:os.environ['RAGNAROK_PVM_COMPARE_'+n] for n in ['BASE','SCOPE','OUTPUT','SYNTHETIC']}))"
        source = '\n'.join(exports)+"\ncompare-pvm-guests:\n\t@python3 -c "+repr(probe)+"\n"
        result = subprocess.run(['make', '--no-print-directory', '-f', '-'], input=source,
            text=True, capture_output=True, check=True,
            env=dict(os.environ, **{'PVM_COMPARE_'+key: value for key, value in values.items()}))
        self.assertEqual(json.loads(result.stdout), values)

    def test_relative_control_output_supports_real_command_logs(self):
        """A relative CLI directory must become absolute before NativeChecks records repository-relative logs."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            output = root/'build/control'
            for name in compare.DRIVER:
                # Only driver presence is needed before the deliberately stopped preparation call.
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'driver fixture')

            def prepare(checks, folder, cases):
                """Exercise real process/log capture, then stop before any compiler or benchmark runs."""
                self.assertTrue(checks.folder.is_absolute())
                self.assertEqual(checks.folder, output.resolve())
                result = checks.command([sys.executable, '-c', 'print("control output probe")'],
                                        'output-probe', cwd=root)
                self.assertEqual(result['exit_code'], 0)
                self.assertEqual(result['log'], 'build/control/output-probe.log')
                raise RuntimeError('stopped after real output probe')

            with patch.object(compare, 'ROOT', root), patch.object(native_checks, 'ROOT', root), \
                    patch.object(compare, 'revision', return_value='a'*40), \
                    patch.object(compare, 'cpu_model', return_value='fixture CPU'), \
                    patch.object(compare, 'installed', return_value=(root/'compiler', None)), \
                    patch.object(compare, 'snapshot', return_value={}), \
                    patch.object(compare, 'digest', return_value='b'*64), \
                    patch.object(compare, 'prepare_inputs', side_effect=prepare):
                with self.assertRaisesRegex(RuntimeError, 'stopped after real output probe'):
                    compare.run('HEAD', folder=os.path.relpath(output, Path.cwd()))
            self.assertEqual((output/'output-probe.log').read_text(), 'control output probe\n')
            self.assertEqual(json.loads((output/'partial.json').read_text())['status'], 'failed')
            self.assertFalse((output/'results.json').exists())

    def test_control_output_cannot_escape_owned_build(self):
        """An output setting cannot retire or create unrelated user directories before setup."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            foreign = root/'keep'
            foreign.mkdir()
            marker = foreign/'results.json'
            marker.write_text('retain')
            with patch.object(compare, 'ROOT', root), patch.object(compare, 'revision') as resolve:
                with self.assertRaisesRegex(ValueError, 'owned build'):
                    compare.run('HEAD', folder=foreign)
            resolve.assert_not_called()
            self.assertEqual(marker.read_text(), 'retain')

    def test_paired_synthetic_matrix_and_raw_samples(self):
        """Host/tiny controls retain all cells and reject missing, duplicated or altered persisted observations."""
        from test_pvm_benchmark import output
        report = complete_report()
        report.update(synthetic_enabled=True, synthetic_runs=[])
        for repeat, order in enumerate((('baseline', 'candidate'), ('candidate', 'baseline'))):
            for mode, engine in compare.MODES.items():
                for variant in order:
                    raw = output(planned=mode == 'planned', memo=mode == 'memo')
                    if variant == 'candidate':
                        # Independent doubled sample durations make every synthetic regression visible.
                        lines = []
                        for line in raw.splitlines():
                            fields = line.split('\t')
                            if fields[0] == 'sample':
                                fields[3] = str(2*int(fields[3]))
                            lines.append('\t'.join(fields))
                        raw = '\n'.join(lines)
                    report['synthetic_runs'].append(dict(variant=variant, mode=mode,
                        pass_index=repeat, stdout=raw, parsed=compare.parse_output(raw, engine)))
        self.assertEqual(compare.summarize(report).count('+100.0%'), 33)
        for kind in ('missing', 'duplicate', 'order', 'raw', 'parsed', 'bool', 'disabled', 'failed'):
            changed = copy.deepcopy(report)
            rows = changed['synthetic_runs']
            if kind == 'missing':
                rows.pop() # An incomplete final control cannot inherit the earlier successful guest table.
            elif kind == 'duplicate':
                rows[-1] = copy.deepcopy(rows[0])
            elif kind == 'order':
                rows[0], rows[1] = rows[1], rows[0]
            elif kind == 'raw':
                rows[0]['stdout'] = rows[0]['stdout'].split('\n', 1)[1]
            elif kind == 'parsed':
                rows[0]['parsed'][0]['samples'][0]['execution_ns'] += 1
            elif kind == 'bool':
                rows[0]['parsed'][0]['samples'][1]['sample'] = True
            elif kind == 'disabled':
                changed['synthetic_enabled'] = False
            else:
                changed['status'] = 'failed'
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                compare.summarize(changed)

    def test_synthetic_fixture_refuses_before_build(self):
        """A changed synthetic fixture is rejected before any benchmark/compiler process starts."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root/'pvm-benchmark.bin'
            fixture.write_bytes(b'changed')
            checks = Mock()
            contracts = {'pvm_benchmark': ('RAGNAROK_PVM_BENCHMARK', fixture,
                                         [(fixture, 'a'*64)])}
            with patch.object(compare, 'ROOT', root), patch.object(compare, 'load_fixture_contracts', return_value=contracts):
                with self.assertRaisesRegex(ValueError, 'changed paired synthetic fixture'):
                    compare.prepare_synthetic(checks, root/'compiler', root/'build',
                                              dict(builds=[], controls=[]), {}, {}, 'a'*40, {})
            checks.build.assert_not_called()

    def test_complete_summary_retains_regressions(self):
        """All unfavorable cells remain visible; summaries do not select only faster samples."""
        summary = compare.summarize(complete_report())
        self.assertEqual(summary.count('+10.0%'), 21)
        self.assertIn('first-cold', summary)

    def test_identical_sources_are_a_control(self):
        """A same-source comparison must not present timing variation as an implemented improvement."""
        report = complete_report()
        report['identical_sources'] = True
        self.assertIn('control variation', compare.summarize(report))

    def test_explicit_control_subset_is_complete(self):
        """The declared non-Pinky subset has its own complete reversed matrix, never a partial default."""
        report = complete_report()
        report['cases'] = report['cases'][:-1]
        report['runs'] = [row for row in report['runs'] if row['guest'] != 'pinky']
        self.assertEqual(compare.summarize(report).count('+10.0%'), 18)

    def test_incomplete_and_duplicate_coverage(self):
        """Failed, missing, repeated, mislabeled and non-reversed processes cannot form a success."""
        valid = complete_report()
        corruptions = []
        failed = copy.deepcopy(valid)
        failed['status'] = 'failed'
        corruptions.append(failed)
        missing = copy.deepcopy(valid)
        missing['runs'].pop()
        corruptions.append(missing)
        duplicate = copy.deepcopy(valid)
        duplicate['runs'][-1] = copy.deepcopy(duplicate['runs'][0])
        corruptions.append(duplicate)
        swapped = copy.deepcopy(valid)
        swapped['runs'][0], swapped['runs'][1] = swapped['runs'][1], swapped['runs'][0]
        corruptions.append(swapped)
        foreign = copy.deepcopy(valid)
        foreign['runs'][0]['parsed']['guest'] = 'memset'
        corruptions.append(foreign)
        boolean = copy.deepcopy(valid)
        boolean['runs'][0]['pass_index'] = False
        corruptions.append(boolean)
        for report in corruptions:
            with self.subTest(report=report['status']), self.assertRaises(ValueError):
                compare.summarize(report)

    def test_every_sample_and_policy_metadata(self):
        """Cold samples, ordered sample IDs and plan/memo preparation remain strict after persistence."""
        for mutate in (lambda r: r['runs'][0]['parsed']['samples'].pop(),
                       lambda r: r['runs'][0]['parsed']['samples'][0].update(cpu_ns=0),
                       lambda r: r['runs'][0]['parsed']['samples'][2].update(sample=1),
                       lambda r: r['runs'][2]['parsed']['preparation'].update(payload_bytes=8),
                       lambda r: r['runs'][4]['parsed']['preparation'].update(priced_blocks=0)):
            report = complete_report()
            mutate(report)
            with self.assertRaises(ValueError):
                compare.summarize(report)

    def test_bounded_cases_and_preparation_identity(self):
        """Guest identity and canonical dimensions cannot drift, including Python's bool/int alias."""
        validate_cases(CASES)
        validate_cases(CASES[:-1])
        self.assertEqual(preparation_identity('GUEST_PREPARED,pinky,1,143,39051\n', 'pinky', 1),
                         dict(mapped_pages=143, code_bytes=39051))
        for cases in ((), CASES[::-1], CASES[:-1]+(('pinky', True),), list(CASES)):
            with self.assertRaises(ValueError):
                validate_cases(cases)
        for output in ('GUEST_PREPARED,memset,1,143,39051\n',
                       'GUEST_PREPARED,pinky,1,0143,39051\n',
                       'GUEST_PREPARED,pinky,1,0,39051\n',
                       'GUEST_PREPARED,pinky,1,1048577,39051\n',
                       'GUEST_PREPARED,pinky,1,143,39051\nextra\n'):
            with self.assertRaises(ValueError):
                preparation_identity(output, 'pinky', 1)

    def test_source_path_and_snapshot_sealing(self):
        """Snapshots preserve exact bytes, retire removed modules and refuse traversal/foreign links."""
        for value in ('../src/pvm/a.nim', '/src/pvm/a.nim', 'src/pvm/../../a.nim',
                      'src/codec/other.nim', 'src/pvm/a.py'):
            with self.assertRaises(ValueError):
                compare.source_path(value)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root/'src/pvm/a.nim'
            source.parent.mkdir(parents=True)
            source.write_text('discard\n')
            codec = root/'src/codec/natural.nim'
            codec.parent.mkdir(parents=True)
            codec.write_text('discard\n')
            target = root/'build/snapshot'
            driver = {name: b'discard\n' for name in compare.DRIVER}
            with patch.object(compare, 'ROOT', root):
                hashes = compare.snapshot(target, None, driver)
                compare.unchanged({target/path: value for path, value in hashes.items()})
                stale = target/'src/pvm/deleted.nim'
                stale.write_text('old\n')
                compare.snapshot(target, None, driver)
                self.assertFalse(stale.exists())
                (target/'src/pvm/a.nim').write_text('changed\n')
                with self.assertRaises(ValueError):
                    compare.unchanged({target/path: value for path, value in hashes.items()})
                source.unlink()
                source.symlink_to(codec)
                with self.assertRaises(ValueError):
                    compare.working_paths()

    def test_canonical_activation_binds_captured_endpoints(self):
        """Both roles compile at one path and changed endpoint bytes refuse before any build."""
        folder = Path('/owned/build/paired')
        endpoints = {'baseline': {'module': 'a'*64}, 'candidate': {'module': 'b'*64}}
        with patch.object(compare, 'snapshot', side_effect=[endpoints['baseline'], endpoints['candidate']]) as freeze:
            first = compare.activate_endpoint(folder, 'baseline', 'c'*40, {}, endpoints)
            second = compare.activate_endpoint(folder, 'candidate', 'c'*40, {}, endpoints)
        self.assertEqual(first, second)
        self.assertEqual(first, folder/'snapshots/compiled')
        self.assertEqual([call.args[1] for call in freeze.call_args_list], ['c'*40, None])
        with patch.object(compare, 'snapshot', return_value={'module': 'changed'}):
            with self.assertRaisesRegex(ValueError, 'endpoint changed'):
                compare.activate_endpoint(folder, 'candidate', 'c'*40, {}, endpoints)
        with self.assertRaisesRegex(ValueError, 'unknown paired compilation variant'):
            compare.activate_endpoint(folder, '../foreign', 'c'*40, {}, endpoints)

    def test_canonical_activation_retires_deleted_members_and_detects_edits(self):
        """Real snapshot activation removes stale modules and binds current bytes to the captured manifest."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('src/pvm/a.nim', 'src/codec/natural.nim'):
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('discard\n')
            driver = {name: b'discard\n' for name in compare.DRIVER}
            with patch.object(compare, 'ROOT', root):
                expected = compare.snapshot(root/'build/captured', None, driver)
                endpoints = {'baseline': expected, 'candidate': expected}
                active = compare.activate_endpoint(root/'build/paired', 'candidate', 'a'*40, driver, endpoints)
                stale = active/'src/pvm/deleted.nim'
                stale.write_text('stale\n')
                compare.activate_endpoint(root/'build/paired', 'candidate', 'a'*40, driver, endpoints)
                self.assertFalse(stale.exists())
                (root/'src/pvm/a.nim').write_text('changed\n')
                with self.assertRaisesRegex(ValueError, 'endpoint changed'):
                    compare.activate_endpoint(root/'build/paired', 'candidate', 'a'*40, driver, endpoints)

    def test_identical_images_cover_every_profile(self):
        """Source-only equality cannot hide a changed guest, legacy or memo executable."""
        endpoints = {'baseline': {'module': 'a'*64}, 'candidate': {'module': 'a'*64}}
        hashes = {name: value*64 for name, value in [('baseline', 'b'), ('candidate', 'b'),
            ('synthetic-baseline-legacy', 'c'), ('synthetic-candidate-legacy', 'c'),
            ('synthetic-baseline-memo', 'd'), ('synthetic-candidate-memo', 'd')]}
        controls = compare.identical_image_controls(endpoints, hashes, True)
        self.assertEqual([row['profile'] for row in controls], ['native', 'synthetic-legacy', 'synthetic-memo'])
        self.assertTrue(all(row['passed'] for row in controls))
        report = dict(compilation_identity_version=1, identical_sources=True, synthetic_enabled=True,
                      endpoints=endpoints, binary_sha256=hashes, identical_image_controls=controls)
        compare.validate_build_identity(report)
        for changed_key in ('candidate', 'synthetic-candidate-legacy', 'synthetic-candidate-memo'):
            # Each real profile independently refuses even when its source manifests remain identical.
            changed = copy.deepcopy(report)
            changed['binary_sha256'][changed_key] = 'e'*64
            changed['identical_image_controls'] = compare.identical_image_controls(endpoints, changed['binary_sha256'], True)
            with self.subTest(profile=changed_key), self.assertRaisesRegex(ValueError, 'native images differ'):
                compare.validate_build_identity(changed)

    def test_image_identity_metadata_cannot_be_dropped_or_retyped(self):
        """Versioned summaries require exact hash/profile coverage and retain bool/int distinctions."""
        endpoints = {'baseline': {'module': 'a'*64}, 'candidate': {'module': 'a'*64}}
        hashes = {'baseline': 'b'*64, 'candidate': 'b'*64}
        report = dict(compilation_identity_version=1, identical_sources=True, synthetic_enabled=False,
            endpoints=endpoints, binary_sha256=hashes,
            identical_image_controls=compare.identical_image_controls(endpoints, hashes, False))
        mutations = [lambda r: r.pop('identical_image_controls'),
                     lambda r: r['binary_sha256'].pop('candidate'),
                     lambda r: r['binary_sha256'].update(candidate=True),
                     lambda r: r.update(compilation_identity_version=True),
                     lambda r: r.update(identical_sources=False),
                     lambda r: r.update(synthetic_enabled=1),
                     lambda r: r['endpoints']['candidate'].update(module=True),
                     lambda r: r['identical_image_controls'][0].update(passed=1)]
        for mutate in mutations:
            changed = copy.deepcopy(report)
            mutate(changed)
            with self.assertRaises(ValueError):
                compare.validate_build_identity(changed)
        ordinary = copy.deepcopy(report)
        ordinary['endpoints']['candidate']['module'] = 'c'*64
        ordinary['binary_sha256']['candidate'] = 'd'*64
        ordinary.update(identical_sources=False, identical_image_controls=[])
        compare.validate_build_identity(ordinary)

    def test_versioned_summary_distinguishes_image_controls_from_historical_sources(self):
        """Historical artifacts remain readable and never gain an unrecorded image-equality claim."""
        report = complete_report()
        report['identical_sources'] = True
        self.assertIn('does not establish native image identity', compare.summarize(report))
        report.update(compilation_identity_version=1, synthetic_enabled=False,
            endpoints={'baseline': {'module': 'a'*64}, 'candidate': {'module': 'a'*64}},
            binary_sha256={'baseline': 'b'*64, 'candidate': 'b'*64})
        report['identical_image_controls'] = compare.identical_image_controls(report['endpoints'], report['binary_sha256'], False)
        self.assertIn('Identical source endpoints and native images', compare.summarize(report))
        report.pop('identical_image_controls')
        with self.assertRaises(ValueError):
            compare.summarize(report)

    def test_changed_same_source_image_stops_before_timing(self):
        """A real orchestration refusal retains failed hashes and retires stale success before any measured process."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            folder = root/'build/paired'
            folder.mkdir(parents=True)
            for name in ('results.json', 'summary.md'):
                (folder/name).write_text('stale')
            for name in compare.DRIVER:
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'driver')
            calls = []
            builds = []

            def fake_build(checks, compiler, source, name, **options):
                """Deliberately unstable compiler output must still fail despite canonical paths."""
                self.assertEqual(name, 'native')
                self.assertEqual(source, folder/'snapshots/compiled'/compare.DRIVER[0])
                binary = checks.folder/name
                builds.append(checks.folder)
                binary.write_bytes(str(len(builds)).encode())
                return {'exit_code': 0}, binary

            def command(checks, arguments, name, **options):
                """Only assertion probes may execute before the image guard; a timed invocation would fail this test."""
                self.assertTrue(name.endswith('-assertion-control'))
                calls.append(name)
                return dict(exit_code=1, output='[Assertion Failure] pvm sieve native assertion control', log=name)

            def digest(path):
                """Only fake build outputs need real unequal digests; unavailable setup files retain a fixed fixture identity."""
                if Path(path).is_file():
                    return inputs.digest(path)
                return 'a'*64

            prepared = dict(identities={}, provenance={}, preparations={}, builds=[], inputs=[])
            with patch.object(compare, 'ROOT', root), patch.object(compare, 'revision', return_value='a'*40), \
                    patch.object(compare, 'cpu_model', return_value='fixture CPU'), \
                    patch.object(compare, 'installed', return_value=(root/'compiler', None)), \
                    patch.object(compare, 'working_paths', return_value=[]), \
                    patch.object(compare, 'snapshot', return_value={'module': 'a'*64}), \
                    patch.object(compare, 'prepare_inputs', return_value=prepared), \
                    patch.object(compare, 'build', side_effect=fake_build), \
                    patch.object(compare, 'digest', side_effect=digest), \
                    patch.object(compare, 'unchanged') as unchanged, \
                    patch.object(native_checks.NativeChecks, 'command', autospec=True, side_effect=command):
                with self.assertRaisesRegex(ValueError, 'identical-source native images differ'):
                    compare.run('HEAD', folder=folder)
            self.assertEqual(len(calls), 2)
            self.assertEqual(builds, [folder/'compilation']*2)
            self.assertEqual(unchanged.call_count, 2)
            failed = json.loads((folder/'partial.json').read_text())
            self.assertEqual(failed['status'], 'failed')
            self.assertFalse(failed['identical_image_controls'][0]['passed'])
            self.assertFalse((folder/'results.json').exists())
            self.assertFalse((folder/'summary.md').exists())

    def test_fresh_canonical_objects_preserve_retained_roles(self):
        """Role builds share exact compiler paths but neither stale cache bytes nor mutable output files."""
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            calls = []

            def fake_build(checks, compiler, source, name, **options):
                """A private marker detects accidental compiler-state reuse between roles."""
                self.assertFalse((checks.folder/'stale-cache').exists())
                (checks.folder/'stale-cache').write_text('retire before next build')
                calls.append(checks.folder)
                image = checks.folder/name
                image.write_bytes(str(len(calls)).encode())
                image.chmod(0o751)
                (checks.folder/(name+'-build.log')).write_text(str(len(calls)))
                return {'exit_code': 0}, image

            with patch.object(compare, 'build', side_effect=fake_build), patch.object(compare, 'ROOT', folder):
                _, first = compare.compile_image(folder, 'baseline', 'compiler', Path('source'), 'native')
                _, second = compare.compile_image(folder, 'candidate', 'compiler', Path('source'), 'native')
            self.assertEqual(calls, [folder/'compilation']*2)
            self.assertEqual(first.read_bytes(), b'1')
            self.assertEqual(second.read_bytes(), b'2')
            self.assertEqual(first.stat().st_mode & 0o777, 0o751)
            self.assertEqual(second.stat().st_mode & 0o777, 0o751)
            self.assertEqual((first.parent/'native-build.log').read_text(), '1')
            self.assertEqual((second.parent/'native-build.log').read_text(), '2')
            (folder/'compilation').rename(folder/'other')
            (folder/'compilation').symlink_to(folder/'other', target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'symlink'):
                compare.compile_image(folder, 'baseline', 'compiler', Path('source'), 'native')

    def test_failed_rerun_retires_success(self):
        """Failure before setup cannot expose the previous completed aggregate or summary."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root/'build/paired'
            folder.mkdir(parents=True)
            for name in ('results.json', 'summary.md'):
                (folder/name).write_text('stale')
            with patch.object(compare, 'ROOT', root), patch.object(compare, 'revision',
                    side_effect=ValueError('refused revision')):
                with self.assertRaises(ValueError):
                    compare.run('missing', folder=folder)
            self.assertFalse((folder/'results.json').exists())
            self.assertFalse((folder/'summary.md').exists())
            self.assertEqual(json.loads((folder/'partial.json').read_text())['status'], 'failed')

    def test_git_revision_is_resolved_without_option_expansion(self):
        """A ref is data, and subsequent reads receive its exact immutable resolved commit."""
        with patch.object(compare, 'git', return_value=b'a'*40+b'\n') as command:
            self.assertEqual(compare.revision('-ref-with-leading-dash'), 'a'*40)
        command.assert_called_once_with('rev-parse', '--verify', '--end-of-options',
                                        '-ref-with-leading-dash^{commit}')
        with self.assertRaises(ValueError):
            compare.revision('')

    def test_revision_tree_uses_literal_nul_delimited_paths(self):
        """Git quoting or embedded whitespace cannot silently omit a module; symlink blobs are refused."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            driver = {name: b'discard\n' for name in compare.DRIVER}
            names = ['src/codec/natural.nim', 'src/pvm/a b.nim']
            tree = ''.join('100644 blob '+'a'*40+'\t'+name+'\0' for name in names).encode()
            with patch.object(compare, 'ROOT', root), patch.object(compare, 'git',
                    side_effect=[tree, b'discard\n', b'discard\n']):
                hashes = compare.snapshot(root/'build/snapshot', 'a'*40, driver)
            self.assertTrue(all(name in hashes for name in names))
            linked = ('120000 blob '+'a'*40+'\tsrc/pvm/foreign.nim\0').encode()
            with patch.object(compare, 'ROOT', root), patch.object(compare, 'git', return_value=linked):
                with self.assertRaises(ValueError):
                    compare.snapshot(root/'build/linked', 'a'*40, driver)

    def test_control_subset_still_verifies_all_fixture_members(self):
        """A changed unselected Pinky license must refuse before any reference build or execution."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            contracts = {}
            for key in ('pvm_guests', 'pvm_pinky', 'pvm_sieve'):
                member = root/key
                member.write_bytes(b'original')
                contracts[key] = (None, root, [(member, inputs.digest(member))])
            (root/'pvm_pinky').write_bytes(b'changed')
            checks = Mock()
            with patch.object(inputs, 'ROOT', root), patch.object(inputs, 'load_fixture_contracts',
                    return_value=contracts):
                with self.assertRaises(ValueError):
                    inputs.prepare_inputs(checks, root/'build', CASES[:-1])
            checks.command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
