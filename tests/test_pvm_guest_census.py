# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect real-guest census invocation identity, bounded capacity and retirement of stale results."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from pvm_guest_census import observation, run
from pvm_opcode_census import ROOT, instrument_step, parse_reports
from pvm_sieve_report import parse_process_output
from test_pvm_opcode_census import report


class GuestCensusTests(unittest.TestCase):
    """A complete census is bound to one checked guest invocation, never accepted as timing evidence."""

    def test_single_invocation_identity(self):
        """Require a complete diagnostic frame, guest family, size, policy and one native sample."""
        census = report(3, [(0, 1), (2, 2)], [(2, 0, 1), (2, 2, 1)])
        native = 'GUEST,minimal\nSIEVE,ragnarok,1000,0,5,4\n'
        valid = census+native
        counted = observation(valid, 'dynamic', 'minimal', 1000)
        self.assertEqual(counted['steps'], 3)
        corruptions = [native, census+census+native, valid.replace('GUEST,minimal', 'GUEST,memset'),
            valid.replace('ragnarok,1000', 'ragnarok_planned,1000'),
            valid.replace('1000,0', '100000,0'), valid.replace(',0,5,4', ',1,5,4'),
            valid.replace(',0,5,4', ',0,0,4'), valid+'SIEVE,ragnarok,1000,1,5,4\n',
            valid.replace('census,end\n', '')]
        for text in corruptions:
            with self.subTest(text=text), self.assertRaises(ValueError):
                observation(text, 'dynamic', 'minimal', 1000)

    def test_measurements_stay_strict(self):
        """One-sample diagnostics require explicit selection; normal timing still requires all thirteen samples."""
        native = 'SIEVE,ragnarok,1000,0,5,4\n'
        self.assertEqual(len(parse_process_output(native, 'ragnarok', 1000, samples=1)['samples']), 1)
        with self.assertRaises(ValueError):
            parse_process_output(native, 'ragnarok', 1000)
        for count in (0, 2, 12, 14, True):
            with self.subTest(count=count), self.assertRaises(ValueError):
                parse_process_output(native, 'ragnarok', 1000, samples=count)

    def test_capacity_contract(self):
        """A connected 513-transition walk exceeds synthetic capacity and is admitted only by the real-guest parser."""
        # Construct a real walk independently: 0,0,1,0,2,0,...,255,0,1,1. It has 513 distinct pairs.
        walk = [0, 0]
        for op in range(1, 256):
            walk.extend((op, 0))
        walk.extend((1, 1))
        ops, pairs = {}, {}
        for op in walk:
            ops[op] = ops.get(op, 0)+1
        for a, b in zip(walk, walk[1:]):
            pairs[a, b] = pairs.get((a, b), 0)+1
        self.assertEqual(len(pairs), 512)
        walk.append(2)
        ops[2] += 1
        pairs[1, 2] = 1
        text = report(len(walk), sorted(ops.items()), [(a, b, n) for (a, b), n in sorted(pairs.items())])
        with self.assertRaises(ValueError):
            parse_reports(text)
        self.assertEqual(parse_reports(text, 4096)[0][0]['steps'], len(walk))
        generated = instrument_step((ROOT/'src/pvm/step.nim').read_text(), 4096)
        self.assertIn('censusPairs: array[4096, CensusPair]', generated)
        self.assertIn('shr 52', generated)
        for capacity in (0, 513, 65536):
            with self.assertRaises(ValueError):
                instrument_step('', capacity)

    def test_stale_result_retired(self):
        """A missing pinned compiler cannot leave a previous successful aggregate available."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root/'build/tests/pvm-guest-census/results.json'
            path.parent.mkdir(parents=True)
            path.write_text('{"stale":true}')
            with patch('pvm_guest_census.ROOT', root), patch('pvm_guest_census.installed', side_effect=ValueError('compiler')):
                with self.assertRaises(ValueError):
                    run()
            self.assertFalse(path.exists())
