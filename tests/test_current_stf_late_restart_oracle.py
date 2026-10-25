# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent source identity, complete checkpoint continuation and exact refusal/success sequencing."""
import json
import unittest
import current_stf_late_restart_oracle as reference
import late_replay_oracle as suite


class LateRestartTests(unittest.TestCase):
    """Only independently expected roots accompany accepted blocks; expected posterior maps are never restore inputs."""

    @classmethod
    def setUpClass(cls):
        """Derive every complete selected source chain before inspecting the separate restart wire boundary."""
        cls.requests,cls.lines,cls.evidence=reference.expected_observations()

    def test_every_restart_transports_only_the_signed_block_and_trusted_root(self):
        """A posterior checkpoint cannot be smuggled into the restart command or substituted for actual captured native bytes."""
        steps=[line.split() for line in self.requests if line.startswith('S ')]
        roots=[root for row in self.evidence['roots'] for root in row]
        self.assertEqual(len(steps),156)
        for step,root in zip(steps,roots):
            self.assertEqual(len(step),3);self.assertEqual(step[2],root);self.assertEqual(len(bytes.fromhex(root)),32)
        self.assertFalse(any(line.startswith(('B ','T ')) for line in self.requests))

    def test_every_selected_named_source_keeps_all_qualified_answers(self):
        """Source fixture identities bind complete roots/checkpoint hashes; selection does not silently trim the difficult suffix."""
        chosen=suite.cases()
        for index,(family,module,name) in enumerate(suite.FAMILIES):
            selected=chosen[index]['source_index'];self.assertEqual(chosen[index]['source_name'],name)
            frozen=json.loads(module.FIXTURE.read_text())['evidence']
            for key in ('roots','checkpoint_sha256','parameters_sha256','inventory_sha256'):
                self.assertEqual(self.evidence[key][index],frozen[key][selected])
        self.assertEqual(self.evidence['origins'],suite.origins());self.assertEqual(self.evidence['chains'],12)

    def test_exact_restore_controls_follow_every_complete_transition(self):
        """Both typed refusals and actual successful reconstruction are mandatory before the next block can execute."""
        outputs=[i for i,line in enumerate(self.lines) if line.startswith('O ')]
        self.assertEqual(len(outputs),156)
        for index in outputs:self.assertEqual(self.lines[index+1:index+4],['K RootMismatch','K LimitExceeded','K Restored'])
        self.assertEqual(self.evidence['checkpoint_refusals'],312)
        self.assertEqual(self.evidence['restarts'],156)

    def test_selected_cases_remain_caller_owned(self):
        """A caller cannot mutate cached nested histories used to derive another caller's expected checkpoint roots."""
        first=suite.cases();second=suite.cases();first[0]['initial'].clear();first[0]['steps'][0][1].clear()
        self.assertEqual(suite.cases(),second);self.assertTrue(second[0]['initial']);self.assertTrue(second[0]['steps'][0][1])


if __name__=='__main__':
    unittest.main()
