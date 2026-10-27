# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent offender/reporting invariants across admission, cancellation and delayed nulling."""
import unittest
from scenario_states import checkpoint_states
import current_stf_offender_reporting_oracle as reference
from state_layout_oracle import chapter_key


class OffenderReportingTests(unittest.TestCase):
    """Inspect complete expected chains; no observed native successor participates in the answers."""

    @classmethod
    def setUpClass(cls):
        """Retain frozen complete maps and exact refusal evidence once per mathematical test group."""
        cls.requests, cls.lines, cls.evidence = reference.expected_observations()
        cls.states = checkpoint_states(cls.lines)

    def test_posterior_guarantees_exclude_offenders_without_shrinking_groups(self):
        """Phi removes signing eligibility while preserving nine assigned positions and two-of-three report thresholds."""
        for case, states in enumerate(self.states):
            parent=states[11]
            gs,ass,disputes=reference.inputs(parent,case,12)
            _,_,offenders=reference.post_disputes(parent,disputes)
            self.assertEqual(len(offenders),1); self.assertEqual(len(gs),3)
            for item in gs:
                roster,assigned=reference.rotation.credentials(parent,12,item['slot'])
                self.assertEqual(len(assigned),len(roster))
                self.assertTrue(2<=len(item['credentials'])<=3)
                self.assertTrue(all(roster[i][32:64] not in offenders for i,_ in item['credentials']))
            self.assertEqual(len(ass),6)
            self.assertEqual(len(reference.reporting.ready(states[12][chapter_key(14)],3)[0]),2)

    def test_assurances_keep_prior_offender_identity_eligibility(self):
        """Prior active scalar6 contributes an assurance even when its guarantee key has been nulled by Phi."""
        for case, states in enumerate(self.states):
            parent=states[11]; gs,ass,disputes=reference.inputs(parent,case,12)
            _,_,offenders=reference.post_disputes(parent,disputes)
            prior=reference.epoch.roster(parent[chapter_key(8)])
            self.assertTrue(any(prior[item['index']][32:64] in offenders for item in ass))
            reference.validate(parent,12,gs,ass,disputes)

    def test_verdict_cancels_before_assurances_and_replacement(self):
        """Bad reports disappear before assurance-bit validity, while a different package can replace their core."""
        for case,states in enumerate(self.states):
            parent=states[16];gs,ass,disputes=reference.inputs(parent,case,17)
            working,_,offenders=reference.post_disputes(parent,disputes)
            old=reference.reporting.pending(parent[chapter_key(10)],3,9)
            filtered=reference.reporting.pending(working[chapter_key(10)],3,9)
            removed=[i for i,(a,b) in enumerate(zip(old,filtered)) if a is not None and b is None]
            self.assertEqual(len(removed),1); core=removed[0]
            self.assertTrue(all(not (a['bits'] & (1<<core)) for a in ass))
            current=reference.reporting.pending(states[17][chapter_key(10)],3,9)
            self.assertEqual(current[core]['registered'],17)
            self.assertNotEqual(current[core]['guarantee']['report'],old[core]['guarantee']['report'])
            self.assertEqual(len(reference.reporting.ready(states[17][chapter_key(14)],3)[5]),2)
            self.assertEqual(len(offenders),2)

    def test_delayed_complete_null_record_and_survivor_assurances(self):
        """Only original scalar6's full staging record is nulled and later promoted; null positions keep their population weight."""
        for states in self.states:
            pending=reference.epoch.consensus(states[12][chapter_key(4)])[0]
            active=reference.epoch.roster(states[12][chapter_key(8)])
            self.assertEqual(pending.count(reference.epoch.NULL_VALIDATOR),1)
            self.assertNotIn(reference.epoch.NULL_VALIDATOR,active)
            self.assertEqual(reference.epoch.roster(states[24][chapter_key(8)]).count(reference.epoch.NULL_VALIDATOR),1)
            gs,ass,disputes=reference.inputs(states[24],0,25)
            self.assertEqual(len(ass),5)
            self.assertEqual([a['index'] for a in ass],[1,2,3,4,5])
            self.assertEqual(states[25][chapter_key(10)],bytes(3))

    def test_frozen_refusals_and_complete_namespace_preservation(self):
        """Exact marker/signature/cancelled-core refusals preserve their classifications and every service entry."""
        self.assertEqual(self.evidence['transitions'],22)
        self.assertEqual(len(self.evidence['refusals']),17)
        self.assertEqual(set(self.evidence['refusals']),{'dispute/InvalidMarker','dispute/InvalidSignature','availability/UnassignedCore','credential/InvalidSignature'})
        mutable={chapter_key(i) for i in (1,3,4,5,6,8,9,10,11,13,14)}
        for states in self.states:
            original=states[1]
            for state in states.values():
                self.assertEqual(set(state),set(original))
                self.assertTrue(all(state[k]==original[k] for k in set(original)-mutable))
