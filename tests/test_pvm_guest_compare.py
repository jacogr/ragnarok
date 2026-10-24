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
                'RAGNAROK_PVM_COMPARE_OUTPUT': 'build/tests/pvm-guest-control'}), patch.object(compare, 'run') as run:
            compare.main()
        run.assert_called_once_with('literal;ref', scope='all', folder='build/tests/pvm-guest-control')
        with patch.dict(compare.os.environ, {'RAGNAROK_PVM_COMPARE_BASE': 'HEAD',
                'RAGNAROK_PVM_COMPARE_SCOPE': 'controls',
                'RAGNAROK_PVM_COMPARE_OUTPUT': ''}), patch.object(compare, 'run') as run:
            compare.main()
        run.assert_called_once_with('HEAD', scope='controls', folder=None)

    def test_make_exports_comparison_settings_literally(self):
        """A workflow baseline ref containing Make syntax must reach Git as data rather than execute it."""
        makefile = (compare.ROOT/'Makefile').read_text()
        exports = [line for line in makefile.splitlines()
                   if line.startswith('compare-pvm-guests: export RAGNAROK_PVM_COMPARE_')]
        self.assertEqual(len(exports), 3)
        names = ('BASE', 'SCOPE', 'OUTPUT')
        values = {name: 'literal-$(shell echo expanded)-'+name for name in names}
        probe = "import os,json; print(json.dumps({n:os.environ['RAGNAROK_PVM_COMPARE_'+n] for n in ['BASE','SCOPE','OUTPUT']}))"
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
