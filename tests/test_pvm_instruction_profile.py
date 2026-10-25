# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Require complete counters, calibrated scope, stable captured C and real source attribution."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from pvm_instruction_profile import (profile_counts, calibration_passed, last_call_calibration_passed, collect, run,
    capture_generated_sources, verify_generated_sources, execution_source_files, source_annotation_passed, machine_profile_counts, disassembly_passed)


def profile(total=42, function='pvm_profile_selected'):
    """Author the documented raw format independently of the profiler runner."""
    return '# callgrind format\nversion: 1\nevents: Ir Bc Bcm Bi Bim\nfn='+function+'\n1 1 0 0 0 0\nsummary: '+str(total)+' 0 0 0 0\ntotals: '+str(total)+' 0 0 0 0\n'


class InstructionProfileTests(unittest.TestCase):
    """Partial files and arbitrary process success cannot certify selected execution."""

    def test_complete_and_empty_counters(self):
        """Keep every event and accept zero only for the deliberately absent-scope control."""
        self.assertEqual(profile_counts(profile()), dict(Ir=42, Bc=0, Bcm=0, Bi=0, Bim=0))
        self.assertEqual(profile_counts(profile(0), allow_empty=True)['Ir'], 0)
        with self.assertRaises(ValueError):
            profile_counts(profile(0))

    def test_real_callgrind_omits_trailing_zero_events(self):
        """The observed Linux format omits zero Bi/Bim costs; it still agrees with the complete header."""
        raw = profile().replace('42 0 0 0 0', '483 32 10')
        self.assertEqual(profile_counts(raw), dict(Ir=483, Bc=32, Bcm=10, Bi=0, Bim=0))

    def test_bad_counters(self):
        """Reject missing/duplicate/truncated/malformed/negative totals and shifted event columns."""
        valid = profile()
        for text in [valid.replace('totals:', 'partial:'), valid+valid, valid.replace('42 0', '-1 0'),
                valid.replace('42 0', '01 0'), valid.replace('42 0', '42.0 0'),
                valid.replace('Ir Bc', 'Bc Ir'), valid.replace('Ir Bc', 'Ir Ir'),
                valid.replace('42 0 0 0 0', '42 0 0 0 0 0'),
                valid.replace('totals: 42', 'totals: 43'), valid.replace('# callgrind format', '# other')]:
            # Every broken file retains the other control fields, isolating its own refusal condition.
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    profile_counts(text)

    def test_selected_and_excluded_scopes(self):
        """Both the selected and deliberately absent function need classified positive process output."""
        good = dict(exit_code=0, output='PVM profile calibration passed\n')
        self.assertTrue(calibration_passed(good, profile(), True))
        self.assertTrue(calibration_passed(good, profile(0), False))
        for result, text, selected in [(dict(exit_code=1, output=good['output']), profile(), True),
                (dict(exit_code=0, output='generic success'), profile(), True),
                (good, profile(function='other'), True), (good, profile()+'fn=pvm_profile_outside\n', True),
                (good, profile(0), True), (good, profile(), False)]:
            # Generic crashes, wrong scopes and whole-process collection are never a calibration fallback.
            self.assertFalse(calibration_passed(result, text, selected))

    def test_last_call_requires_exact_selected_work_and_complete_counts(self):
        """Reset calibration rejects missing work, retained warmup, partial data and wrong scope."""
        self.assertTrue(last_call_calibration_passed(profile(), profile(84), profile()))
        for single, repeated, final in [
                (profile(), profile(), profile()), (profile(), profile(84), profile(84)),
                (profile(), profile(84), profile(41)), (profile(0), profile(0), profile(0)),
                (profile(), profile(84).replace('totals:', 'partial:'), profile()),
                (profile(), profile(84), profile(function='other')),
                (profile(function='pvm_profile_selected_suffix'), profile(84), profile()),
                (profile(), profile(84), profile()+'fn=pvm_profile_outside\n')]:
            # Independent failures preserve all unrelated calibration fields.
            with self.subTest(single=single, repeated=repeated, final=final):
                self.assertFalse(last_call_calibration_passed(single, repeated, final))

    def test_collection_controls_entry_reset_and_argument_placement(self):
        """Existing calls stay unchanged; explicit last-call collection resets only its selected scope."""
        class Checks:
            """A command recorder produces a fresh raw file without provisioning native tools."""
            def __init__(self, folder):
                self.folder = folder
                self.calls = []

            def command(self, command, name, **options):
                self.calls.append((command, name, options))
                output = Path(next(item.split('=', 1)[1] for item in command
                                   if str(item).startswith('--callgrind-out-file=')))
                output.write_text(profile())
                return dict(exit_code=0, output='selected')

        with tempfile.TemporaryDirectory() as directory:
            checks = Checks(Path(directory))
            for reset in (False, True):
                # A private output is retired on both normal and reset collections.
                (checks.folder/'sample.callgrind').write_text('stale')
                _, output = collect(checks, 'binary', 'sample', 'selected', {}, 30,
                    instructions=True, reset_each_call=reset, arguments=('twice',))
                command = checks.calls[-1][0]
                self.assertEqual(command[-2:], ['binary', 'twice'])
                self.assertEqual('--zero-before=selected' in command, reset)
                self.assertIn('--dump-instr=yes', command)
                self.assertEqual(output.read_text(), profile())
            with patch.object(checks, 'command', return_value=dict(exit_code=0, output='')):
                # A successful command without fresh counters cannot reuse an earlier file.
                with self.assertRaises(RuntimeError):
                    collect(checks, 'binary', 'sample', 'selected', {}, 30)
            self.assertFalse((checks.folder/'sample.callgrind').exists())

    def test_generated_sources_preserve_recorded_paths_and_identity(self):
        """Copied source reproduces relative DWARF paths; missing/changed copies or originals fail."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root/'build/profile'
            source = folder/'compiler-pin/guest-cache/c/pkg/step.c'
            source.parent.mkdir(parents=True)
            source.write_text('void execute_1_test(void) {}\n')
            stale = folder/'generated-source/stale.c'
            stale.parent.mkdir()
            stale.write_text('old source')
            archive, manifest = capture_generated_sources(folder, root)
            key = source.relative_to(root).as_posix()
            copied = archive/key
            self.assertEqual(copied.read_bytes(), source.read_bytes())
            self.assertFalse(stale.exists())
            verify_generated_sources(manifest, root, archive)
            for path in [copied, source]:
                # A valid capture cannot certify later byte changes on either side of the archive.
                original = path.read_bytes()
                path.write_bytes(original.replace(b'void', b'VOID'))
                with self.assertRaises(ValueError):
                    verify_generated_sources(manifest, root, archive)
                path.write_bytes(original)
            copied.unlink()
            with self.assertRaises(ValueError):
                verify_generated_sources(manifest, root, archive)

    def test_empty_and_escaping_generated_sources_are_refused(self):
        """An unrelated cache or an external symlink cannot stand in for guest-generated C."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root/'build/profile'
            folder.mkdir(parents=True)
            with self.assertRaises(ValueError):
                capture_generated_sources(folder, root)
            outside = root/'outside.c'
            outside.write_text('external source')
            source = folder/'compiler-pin/guest-cache/c/pkg/step.c'
            source.parent.mkdir(parents=True)
            try:
                # Platforms without symlink support retain the positive/mutation controls above.
                source.symlink_to(outside)
            except OSError:
                self.skipTest('symlinks unavailable')
            with self.assertRaises(ValueError):
                capture_generated_sources(folder, root)

    def test_selected_sources_require_exact_captured_file_bindings(self):
        """Only uncompressed selected functions mapped to captured generated paths grant attribution."""
        key = 'build/profile/compiler-pin/guest-cache/c/pkg/step.c'
        raw = 'fl='+key+'\nfn=execute_1_test\n1 42\n'
        self.assertEqual(execution_source_files(raw, {key: {}}), [key])
        for text in [raw.replace(key, '../outside.c'), raw.replace('fl=', 'cfl='),
                raw.replace('fl='+key, 'fl=(1) '+key), raw.replace('fn=execute_1_test', 'fn=other')]:
            # Caller-only metadata, aliases and foreign files never cause fallback path reads.
            with self.assertRaises(ValueError):
                execution_source_files(text, {key: {}})

    def test_source_sections_are_required_beyond_function_summary(self):
        """Missing source, a wrong file, failed annotation or a summary header cannot pass."""
        key = 'build/profile/compiler-pin/guest-cache/c/pkg/step.c'
        good = dict(exit_code=0, output='PROGRAM TOTALS\n-- User-annotated source: '+key+'\n42 1 code\n')
        self.assertTrue(source_annotation_passed(good, [key]))
        for result in [dict(good, exit_code=1), dict(good, output='PROGRAM TOTALS\n'),
                dict(good, output='PROGRAM TOTALS\nUser annotated: '+key),
                dict(good, output=good['output'].replace(key, key+'.other'))]:
            self.assertFalse(source_annotation_passed(result, [key]))
        self.assertFalse(source_annotation_passed(good, []))

    def test_machine_trace_requires_positions_scope_and_equal_work(self):
        """An instruction trace cannot substitute a different function, workload or source-only dump."""
        raw = profile(function='execute_1_test').replace('version: 1', 'version: 1\npositions: instr line')
        self.assertEqual(machine_profile_counts(raw, {'Ir': 42})['Ir'], 42)
        for text, reference in [(raw, {'Ir': 43}), (raw.replace('instr line', 'line'), {'Ir': 42}),
                (raw.replace('instr line', 'instr instr line'), {'Ir': 42}),
                (raw.replace('execute_1_test', 'other'), {'Ir': 42}),
                (raw.replace('positions: instr line', 'positions: instr line\npositions: instr line'), {'Ir': 42})]:
            # Each independent mismatch retains valid footer counts, preventing generic-format fallback.
            with self.subTest(text=text, reference=reference):
                with self.assertRaises(ValueError):
                    machine_profile_counts(text, reference)

    def test_disassembly_requires_native_code_and_execution_symbol(self):
        """A successful tool header, foreign architecture or symbol table alone is not disassembled execution."""
        output = 'guest: file format elf64-x86-64\n00001000 <execute_1_test>:\n    1000: ret\n'
        good = dict(exit_code=0, output=output)
        self.assertTrue(disassembly_passed(good))
        for result in [dict(good, exit_code=1), dict(good, output=output.replace('elf64-x86-64', 'elf64-aarch64')),
                dict(good, output=output.replace('execute_1_test', 'other')),
                dict(good, output=output.replace('    1000: ret\n', ''))]:
            self.assertFalse(disassembly_passed(result))

    def test_refusal_retires_completed_reports(self):
        """An unsupported local host cannot leave an old successful aggregate available."""
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            for name in ('results.json', 'summary.md', 'generated-source-manifest.json',
                         'native-disassembly.log', 'pinky-1-planned-instructions.callgrind'):
                (folder/name).write_text('stale success')
            with patch('pvm_instruction_profile.BUILD', folder), patch(
                    'pvm_instruction_profile.platform.system', return_value='unsupported'):
                with self.assertRaises(RuntimeError):
                    run()
            self.assertFalse((folder/'results.json').exists())
            self.assertFalse((folder/'summary.md').exists())
            self.assertFalse((folder/'generated-source-manifest.json').exists())
            self.assertFalse((folder/'native-disassembly.log').exists())
            self.assertFalse((folder/'pinky-1-planned-instructions.callgrind').exists())
            self.assertIn('failed', (folder/'partial.json').read_text())
