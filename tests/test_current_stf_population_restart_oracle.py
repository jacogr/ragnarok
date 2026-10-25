# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent restart trust inputs, full-chain selection and original qualified-answer preservation."""
import json
import unittest
import current_stf_population_restart_oracle as reference
import reporting_replay_oracle as suite


class PopulationRestartTests(unittest.TestCase):
    """Expected roots alone authorize native checkpoint reconstruction; posterior maps remain comparison output."""

    @classmethod
    def setUpClass(cls):
        """Generate complete independent inputs once and retain source-origin identity separately."""
        cls.requests,cls.lines,cls.evidence=reference.expected_observations()

    def test_each_restart_supplies_only_block_and_independent_root(self):
        """Every accepted block receives its mathematical root without transporting a posterior checkpoint into reconstruction."""
        roots=[root for chain in self.evidence['roots'] for root in chain]
        steps=[line.split() for line in self.requests if line.startswith('S ')]
        self.assertEqual(len(steps),102)
        for fields,root in zip(steps,roots):
            self.assertEqual(len(fields),3);self.assertEqual(fields[2],root);self.assertEqual(len(bytes.fromhex(fields[2])),32)
        self.assertFalse(any(line.startswith('B ') for line in self.requests))

    def test_all_original_chain_roots_and_complete_map_hashes_remain_exact(self):
        """Selection preserves every transition of each original qualified chain, including difficult suffixes."""
        index=0
        for family,module,selection in suite.FAMILIES:
            frozen=json.loads(module.FIXTURE.read_text())['evidence']
            for original in selection:
                self.assertEqual(self.evidence['roots'][index],frozen['roots'][original])
                self.assertEqual(self.evidence['checkpoint_sha256'][index],frozen['checkpoint_sha256'][original]);index+=1
        self.assertEqual(index,9)

    def test_every_restart_requires_two_refusals_and_complete_success(self):
        """Partial restoration or a successful wrong-root decode cannot satisfy the exact complete observation sequence."""
        outputs=[i for i,line in enumerate(self.lines) if line.startswith('O ')]
        self.assertEqual(len(outputs),self.evidence['restarts'])
        for index in outputs:self.assertEqual(tuple(self.lines[index+1:index+4]),reference.CONTROLS)
        self.assertEqual(self.evidence['checkpoint_refusals'],204)

    def test_state_families_and_explicit_configuration_are_retained(self):
        """Offenders, three guest modes, tickets, release/resize-clear waves, deferred gas and historical anchors all restart."""
        self.assertEqual({family for family,_ in self.evidence['origins']},{'offenders','guests','tickets','waves','gas','anchors'})
        self.assertEqual((self.evidence['chains'],self.evidence['transitions']),(9,102))
        parameters=self.evidence['parameters_sha256'];self.assertEqual(len(parameters),9)
        self.assertIsNotNone(parameters[-1]);self.assertTrue(all(value is None for value in parameters[:-1]))

    def test_case_selection_rejects_empty_duplicate_or_out_of_range_ids(self):
        """Focused replay never weakens the original complete corpus schedule or silently accepts an empty selection."""
        for module in (suite.waves,suite.gas):
            for selection in ((),(0,0),(-1,),(1000,)):
                with self.subTest(module=module.__name__,selection=selection):
                    with self.assertRaises(AssertionError):module.cases(selection)
