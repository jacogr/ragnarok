# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Refuse partial, doubled or incorrectly scoped costs in comparative interpreter diagnosis."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from pvm_interpreter_diagnosis import incoming_entries, return_parts, self_costs


def profile(count=30):
    """Use a complete raw profile whose caller edge includes the same callee work."""
    return (f'# callgrind format\npositions: instr line\nevents: Ir Bc\nsummary: {count}\n'
            'fn=caller\ncfn=selected\ncalls=1 0x10 0\n0x10 0 30\n'
            'fn=selected\n0x20 0 10\n+1 0 20\n'+f'totals: {count}\n')


class DiagnosisTests(unittest.TestCase):
    """Validate independent call-edge accounting and bounded initialization/warmup dumps."""

    def test_self_costs_exclude_inclusive_edges(self):
        """The caller's inclusive 30 instructions must not double its callee's 30 self instructions."""
        self.assertEqual(self_costs(profile()), [('selected', 30)])
        for text in (profile(31), profile().replace('totals: 30', 'totals: 29'),
                     profile().replace('positions: instr line', 'positions: line')):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self_costs(text)

    def test_entry_scope_counts_only_selected_calls(self):
        """Unrelated or zero-count ancestor edges cannot certify a selected invocation."""
        self.assertEqual(incoming_entries(profile(), ['selected']), 1)
        self.assertEqual(incoming_entries(profile(), ['other']), 0)
        self.assertEqual(incoming_entries(profile().replace('calls=1', 'calls=0'), ['selected']), 0)
        self.assertEqual(incoming_entries(profile().replace('calls=1', 'calls=13'), ['selected']), 13)

    def test_fourteen_returns_include_reference_initializer(self):
        """Thirteen reference frames plus one initializer need fourteen complete return parts."""
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)/'guest.callgrind'
            output.write_text(profile(0).replace('0x20 0 10\n+1 0 20\n', ''))
            for index in range(1, 15):
                Path(str(output)+'.'+str(index)).write_text(profile())
            self.assertEqual(len(return_parts(output, 14)), 14)
            with self.assertRaises(ValueError):
                return_parts(output, 13)
            Path(str(output)+'.7').write_text(profile().replace('totals:', 'partial:'))
            with self.assertRaises(ValueError):
                return_parts(output, 14)


if __name__ == '__main__':
    unittest.main() # Focused local checks do not build or execute native workloads.
