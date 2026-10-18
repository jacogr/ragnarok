# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Gas fixture provenance, pinned compatible timelines and explicit specification gates."""
import hashlib
import json
import re
import unittest
from dependencies import require_submodule
from pvm_gas_reference import ROOT, tables, fixtures, simulate, instruction, upstream_cases, cost


# The model is test-only; these assertions never invoke production code to generate expectations.
class GasReferenceTests(unittest.TestCase):
    # Whole source hashes bind both the normative equations and the upstream cross-checks.
    def test_pinned_sources(self):
        pins = json.loads((ROOT/'spec/pins.json').read_text())['graypaper']
        self.assertEqual(hashlib.sha256((ROOT/pins['path']/'text/pvm.tex').read_bytes()).hexdigest(),
                         pins['source_sha256']['text/pvm.tex'])
        upstream = json.loads((ROOT/'spec/polkavm-pins.json').read_text())
        path = require_submodule(upstream)
        for name in ('crates/polkavm-common/src/simulator.rs', 'LICENSE-MIT'):
            # Read only pinned source text; no upstream compiler or execution is required.
            self.assertEqual(hashlib.sha256((path/name).read_bytes()).hexdigest(), upstream['source_sha256'][name])
        self.assertTrue((ROOT/'tests/fixtures/pvm-gas.LICENSE').read_bytes().endswith((path/'LICENSE-MIT').read_bytes()))

    # Independent state transitions must exactly regenerate the frozen native binary.
    def test_reproducible_fixture(self):
        data, count = fixtures()
        self.assertGreater(count, 1000)
        self.assertEqual(data, (ROOT/'tests/fixtures/pvm-gas.bin').read_bytes())

    # Selected timelines use compatible register-only costs, excluding PolkaVM's four-cycle L1 loads.
    def test_upstream_timelines(self):
        text = (ROOT/'vendor/polkavm/crates/polkavm-common/src/simulator.rs').read_text()
        definitions = tables()
        for name, sequence in upstream_cases().items():
            # Select exact named test bodies and extract only their fixed timeline strings.
            body = re.search(r'fn test_'+name+r'\(\) \{(.*?)\n    \}', text, re.S)[1]
            strings = re.findall(r'"([^"\n]*(?:\n[^"\\]*)*)"', body)
            timeline = strings[-1]
            widths = [len(line.strip().split('  ')[0]) for line in timeline.splitlines() if line.strip()]
            self.assertTrue(widths, name)
            self.assertEqual(simulate(sequence, definitions)[0], max(widths)-3, name)

    # Dependency sets include fallback destinations, while shift discounts only inspect the value source.
    def test_table_roles_and_overlap(self):
        definitions = tables()
        self.assertEqual(definitions[0][147][1:], ({'A', 'B'}, {'A'}))
        self.assertEqual(definitions[0][218][1:], ({'A', 'B', 'D'}, {'D'}))
        self.assertEqual(definitions[0][180][1:], ({'B'}, {'A'}))
        self.assertEqual(definitions[0][10][1:], (set(), set()))
        for destination, slots in ((0, 2), (1, 3), (2, 3)):
            # Overwriting B does not qualify for the variable-shift A/D discount.
            raw = instruction(207, 0, 1, destination)
            self.assertEqual(cost(raw, raw+b'\0', 0, definitions)[3], slots)

    # The independent model refuses negative target indexing instead of using Python's wraparound indexing.
    def test_negative_target_gate(self):
        with self.assertRaisesRegex(ValueError, 'negative branch target'):
            simulate([instruction(170, displacement=-1), instruction(0)], tables())

    @unittest.skip('GP 0.8.0 branch-cost byte lookup has no definition for a negative target; upgrade/clarification required')
    def test_negative_target_consensus_charge(self):
        # This scope gate must be resolved before claiming pricing for every admissible program.
        self.fail('A normative negative-index branch gas cost is required')


# Direct invocation checks provenance and expectations without rewriting the fixture.
if __name__ == '__main__':
    unittest.main()
