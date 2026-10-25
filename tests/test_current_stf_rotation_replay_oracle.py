# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-history restart roots and authenticated trace framing/refusal invariants."""
import unittest
import current_stf_rotation_restart_oracle as restart
import current_stf_rotation_trace_oracle as trace
from state_trace_wire_oracle import prefix
from state_layout_oracle import chapter_key


class RotationReplayTests(unittest.TestCase):
    """No native observations can select expected root, framing or accepted-prefix progress."""

    @classmethod
    def setUpClass(cls):
        """Freeze exact input/output families before comparing transport-specific controls."""
        cls.restart=restart.expected_observations();cls.trace=trace.expected_observations()

    def test_callers_cannot_mutate_private_cached_histories(self):
        """A caller's edited initial map, parameter or step list never replaces independently calculated answers."""
        first=trace.suite.cases();second=trace.suite.cases()
        key=next(iter(first[0]['initial']));original=second[0]['initial'][key]
        first[0]['initial'][key]=b'changed';first[0]['steps'].clear()
        self.assertEqual(second[0]['initial'][key],original)
        self.assertGreater(len(second[0]['steps']),0)
        self.assertEqual(trace.suite.cases(),second)

    def test_same_complete_histories_and_roots(self):
        """Checkpoint and trace paths preserve the same finite source selection and every complete map."""
        a,b=self.restart[2],self.trace[2]
        self.assertEqual(a['roots'],b['roots']);self.assertEqual(a['checkpoint_sha256'],b['checkpoint_sha256'])
        self.assertEqual(a['origins'],b['origins']);self.assertEqual(a['chains'],7)
        self.assertEqual(a['restarts'],a['transitions']);self.assertEqual(a['checkpoint_refusals'],2*a['transitions'])
        self.assertEqual(b['trace_refusals'],3*b['transitions'])

    def test_each_restart_has_independently_bound_root(self):
        """Every signed block carries exactly its own independently calculated posterior root."""
        inputs,outputs,evidence=self.restart
        roots=[root for row in evidence['roots'] for root in row]
        actual=[line.rsplit(' ',1)[1] for line in inputs if line.startswith('S ')]
        self.assertEqual(actual,roots)
        for control in ('K RootMismatch','K LimitExceeded','K Restored'):
            self.assertEqual(outputs.count(control),len(roots))

    def test_trace_pre_maps_form_one_exact_continuation(self):
        """Trace framing preserves every previous independently expected map, with exact typed refusal rows."""
        inputs,outputs,evidence=self.trace
        import block_oracle
        source=iter(trace.suite.cases());parent=None;steps=None;count=0
        for line in inputs:
            if line.startswith('C '):
                case=next(source);parent=case['initial'];steps=iter(case['steps'])
            elif line.startswith('T '):
                wire=bytes.fromhex(line[2:]);pairs,extent=prefix(wire)
                self.assertEqual(dict(pairs),parent)
                size,_,_=block_oracle.parse('B',wire[extent:],(3,9,*block_oracle.TINY[2:]))
                block,state,_=next(steps)
                self.assertEqual(wire[extent:extent+size],block)
                after,consumed=prefix(wire[extent+size:])
                self.assertEqual(dict(after),state);self.assertEqual(extent+size+consumed,len(wire))
                parent=state;count+=1
        self.assertEqual(count,evidence['transitions'])
        for control in ('R PreStateMismatch','R PostStateMismatch','R CandidateFailure'):
            self.assertEqual(outputs.count(control),count)


if __name__=='__main__':
    unittest.main()
