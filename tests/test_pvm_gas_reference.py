# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Gas fixture provenance, pinned compatible timelines and explicit specification gates.

Exposes GasReferenceTests for unittest discovery; direct invocation validates generated fixture contracts."""
import hashlib
import json
import re
import unittest
import tempfile
from dependencies import require_submodule
from pvm_gas_reference import ROOT, tables, fixtures, simulate, instruction, upstream_cases, cost, prepare


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

    # Independent state transitions must exactly regenerate the generated native binary.
    def test_reproducible_fixture(self):
        data, count = fixtures()
        self.assertGreater(count, 1000)
        self.assertEqual(hashlib.sha256(data).hexdigest(),
                         '238efdc7d487763e9c50b109b5d43c2543dd05cb2db621e11f4b83d88050e255')
        with tempfile.TemporaryDirectory() as folder:
            # Native input is generated under a caller-owned build directory, never checked in.
            path, evidence = prepare(folder)
            self.assertEqual(data, path.read_bytes())
            self.assertEqual(evidence['fixture_sha256'], hashlib.sha256(data).hexdigest())

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

    # Pinned PolkaVM wraps static targets to u32; Python negative indexing must never select a trailing byte.
    def test_wrapped_negative_targets(self):
        definitions = tables()
        for op in [*range(81, 91), *range(170, 176)]:
            # All immediate/register conditional forms receive the same absent-target prediction hit.
            for displacement in (-1, -128, -(1 << 31)):
                sequence = [instruction(op, displacement=displacement), instruction(100), instruction(0)]
                self.assertEqual(cost(sequence[0], b''.join(sequence), 0, definitions)[2], 1)
                self.assertEqual(simulate(sequence, definitions), (1, 4))

    # The former pending consensus charge now has an explicit first-block cost and independent cycle count.
    def test_negative_target_consensus_charge(self):
        sequence = [instruction(170, displacement=-1), instruction(100), instruction(0)]
        self.assertEqual(simulate(sequence, tables()), (1, 4))


# Direct invocation checks provenance and expectations without rewriting the fixture.
if __name__ == '__main__':
    unittest.main()
