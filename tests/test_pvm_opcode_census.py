# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Require complete consistent opcode graphs and fail-closed snapshot instrumentation/calibration."""
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from pvm_opcode_census import ROOT, instrument_step, parse_reports, calibration_passed, main, snapshot_sources


def report(steps, ops, pairs):
    """Author complete diagnostic records independently of the generated Nim reporter."""
    lines = [f'census,begin,{steps}']
    lines += [f'census,op,{op},{count}' for op, count in ops]
    lines += [f'census,pair,{a},{b},{count}' for a, b, count in pairs]
    return '\n'.join([*lines, 'census,end'])+'\n'


class OpcodeCensusTests(unittest.TestCase):
    """Counts are diagnostic data, never a fallback performance or partial-state success."""

    def test_complete_record(self):
        """A repeated opcode, terminal opcode and all transitions conserve one invocation."""
        text = report(3, [(0, 1), (2, 2)], [(2, 0, 1), (2, 2, 1)])
        rows, regular = parse_reports(text+'other\n'+text)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0], rows[1])
        self.assertEqual(rows[0]['steps'], 3)
        self.assertEqual(regular, 'other\n')

    def test_corrupt_records(self):
        """Reject missing framing, duplicate/range/count corruption, interleaving and disconnected graphs."""
        valid = report(3, [(0, 1), (2, 2)], [(2, 0, 1), (2, 2, 1)])
        broken = [valid.replace('census,end\n', ''), valid+'census,end\n',
            valid.replace('begin,3', 'begin,4'), valid.replace('op,0,1', 'op,0,1\ncensus,op,0,1'),
            valid.replace('op,0,1', 'op,256,1'), valid.replace('op,0,1', 'op,0,01'),
            valid.replace('pair,2,0,1', 'pair,2,3,1'), valid.replace('begin,3', 'begin,18446744073709551616'),
            valid.replace('op,0,1', 'op,0,-1'), valid.replace('op,0,1', 'unexpected\ncensus,op,0,1'),
            report(3, [(0, 1), (2, 2)], [(2, 2, 2)])]
        for text in broken:
            # Every corruption keeps enough surrounding syntax to exercise its own broken obligation.
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    parse_reports(text)

    def test_instrumentation_sites(self):
        """Missing/duplicated/previously injected sites fail before compilation; the production file stays byte-identical."""
        path = ROOT/'src/pvm/step.nim'
        source = path.read_text()
        generated = instrument_step(source)
        self.assertIn('recordCensus(cache, item.opcode)', generated)
        self.assertEqual(path.read_text(), source)
        for capacity in (4, 256, 1024):
            # Production cache tuning must neither remove diagnostic fields nor alter the tuned array.
            tuned = source.replace('array[256, DynamicTargetEntry]', f'array[{capacity}, DynamicTargetEntry]')
            instrumented = instrument_step(tuned)
            self.assertIn(f'targets: array[{capacity}, DynamicTargetEntry]', instrumented)
            self.assertEqual(instrumented.count('    censusOps: array[256, uint64]'), 1)
        for text in [source+source,
                     source.replace('  ExecutionCache = object', '  ChangedCache = object'),
                     source.replace('proc cachedSecondaryCharge(', 'proc changed('), generated]:
            with self.assertRaises(ValueError):
                instrument_step(text)

    def test_nested_sources_are_captured_with_original_identity(self):
        """A shared internal module remains present and hashed in the independently instrumented snapshot."""
        import hashlib
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)/'source'
            names = ['src/pvm/step.nim', 'src/pvm/internal/register_ops.nim',
                     'src/codec/natural.nim', 'tests/performance/pvm_workload.nim',
                     'tests/support/pvm_census_control.nim']
            for name in names:
                # Distinct immutable bytes make a missing or substituted nested input observable.
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(name+'\n')
            folder = Path(directory)/'snapshot'
            with patch('pvm_opcode_census.ROOT', root), patch('pvm_opcode_census.instrument_step',
                    side_effect=lambda source, capacity: source+'instrumented\n'):
                original, generated = snapshot_sources(folder)
            self.assertEqual(set(original), set(names))
            for name in names:
                expected = (root/name).read_bytes()
                self.assertEqual(original[name], hashlib.sha256(expected).hexdigest())
                if name == 'src/pvm/step.nim':
                    # Only the execution observer changes snapshot bytes.
                    expected += b'instrumented\n'
                self.assertEqual((folder/name).read_bytes(), expected)
                self.assertEqual(generated[name], hashlib.sha256(expected).hexdigest())

    def test_calibration(self):
        """Fresh, nested, outer and terminal records remain separate under both callback forms."""
        small = report(3, [(0, 1), (2, 2)], [(2, 0, 1), (2, 2, 1)])
        outer = report(2, [(10, 1), (50, 1)], [(10, 50, 1)])
        terminal = report(1, [(10, 1)], [])
        output = small*3+outer+small+outer+terminal*2+'PVM opcode census controls passed\n'
        self.assertTrue(calibration_passed(dict(exit_code=0, output=output)))
        self.assertFalse(calibration_passed(dict(exit_code=0, output=output.replace(terminal, '', 1))))
        error = '[Assertion Failure] opcode census pair capacity exceeded\n'
        self.assertTrue(calibration_passed(dict(exit_code=1, output=error), capacity=True))
        for code, text in [(0, error), (1, 'crash'), (1, 'census,begin,1\n'+error)]:
            self.assertFalse(calibration_passed(dict(exit_code=code, output=text), capacity=True))

    def test_stale_report_removed(self):
        """An invalid/missing input contract cannot leave a prior aggregate result in place."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root/'build/tests/pvm-census/results.json'
            target.parent.mkdir(parents=True)
            target.write_text('{"stale":true}')
            (root/'tools').mkdir()
            for name in ('pvm_opcode_census.py', 'native_checks.py', 'pvm_benchmark_report.py'):
                (root/'tools'/name).write_text('source identity control')
            with patch('pvm_opcode_census.ROOT', root), patch('pvm_opcode_census.load_fixture_contracts', side_effect=ValueError('input')):
                # Valid source identities cannot turn the deliberately refused input contract into stale aggregate success.
                with self.assertRaises(ValueError):
                    main()
            self.assertFalse(target.exists())
