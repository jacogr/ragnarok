# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent ticket contest, exact body commitment and report/roster invariants."""
import unittest
from scenario_states import checkpoint_states
import current_stf_ticket_reporting_oracle as reference
from state_layout_oracle import chapter_key, digest
from state_statistics_oracle import parse as statistics_parse, DEFAULT
from test_current_stf_epoch_oracle import header_parts


class TicketReportingTests(unittest.TestCase):
    """Retain mathematical complete maps and signed blocks separately from native execution."""

    @classmethod
    def setUpClass(cls):
        """Freeze complete outputs once and retain headers alongside their exact successor maps."""
        _, lines, cls.evidence = reference.expected_observations()
        cls.states = checkpoint_states(lines)
        cls.blocks = []
        for line in lines:
            # Keep ticket-specific signed header observations separate from checkpoint indexing.
            if line.startswith('P '):
                cls.blocks.append({})
            elif line.startswith('B '):
                block = bytes.fromhex(line[2:])
                cls.blocks[-1][int.from_bytes(block[96:100], 'little')] = block

    def test_contest_saturation_selects_tickets_only_after_tail(self):
        """A full contest requires the observed tail to choose ticket sealing; skipped/incomplete tails choose fallback."""
        for i,chain in enumerate(self.states):
            _,_,kind,_,_=reference.epoch.consensus(chain[12][chapter_key(4)])
            self.assertEqual(kind,0 if i==0 else 1)
            self.assertEqual(reference.epoch.consensus(chain[24][chapter_key(4)])[2],1)
        _,winners,_,_=header_parts(self.blocks[0][10]);self.assertEqual(len(winners),12)
        self.assertIsNone(header_parts(self.blocks[2][10])[1])

    def test_ticket_and_reporting_families_coexist_in_exact_wire(self):
        """Slot3 carries three tickets and two genuine guarantees, both included in the header commitment."""
        bank=reference.epoch.bank_records(reference.json.loads(reference.epoch.FIXTURE.read_text()))
        for chain,blocks in zip(self.states,self.blocks):
            parent=chain[2];gs=[reference.population.guarantee(parent,c,3,3,3) for c in range(2)]
            raw,commitment=reference.reporting.body(gs,[],tickets=reference.tickets_wire(bank[3:6]))
            block=blocks[3];self.assertTrue(block.endswith(raw));self.assertEqual(block[64:96],commitment)
            empty_commitment=reference.reporting.body(gs,[])[1];self.assertNotEqual(commitment,empty_commitment)

    def test_epoch_marker_pending_count_and_active_credentials_differ(self):
        """At12 the epoch marker advertises nine pending keys while the actual active report population remains six."""
        for chain,blocks in zip(self.states,self.blocks):
            marker,_,author,_=header_parts(blocks[12]);self.assertEqual(len(marker[2]),9);self.assertLess(author,6)
            self.assertEqual(len(reference.epoch.roster(chain[12][chapter_key(8)])),6)
            self.assertEqual(len(reference.epoch.roster(chain[24][chapter_key(8)])),9)
            self.assertEqual(len(reference.reporting.pending(chain[24][chapter_key(10)],3,9)),3)

    def test_prior_assurances_and_posterior_reporters_keep_separate_rosters(self):
        """Prior-six quorum releases before nine-member assignment and statistics projection at24."""
        for chain in self.states:
            (current,previous,cores,_),_=statistics_parse(chain[24][chapter_key(13)],(3,9,6,*DEFAULT[3:]))
            self.assertEqual((len(current),len(previous)),(9,6));self.assertEqual([r[1] for r in cores],[5,5,0])
            self.assertTrue(all(x is None for x in reference.reporting.pending(chain[25][chapter_key(10)],3,9)))

    def test_body_override_cannot_replace_declared_tickets(self):
        """Composed body overrides must preserve exact independently validated ticket bytes."""
        parent=reference.original();bank=reference.epoch.bank_records(reference.json.loads(reference.epoch.FIXTURE.read_text()))
        with self.assertRaises(AssertionError):
            reference.epoch.successor(parent,2,bank[:3],bank,dict(pending=reference.epoch.consensus(parent[chapter_key(4)])[1]),cores=3,body_override=bytes(7),extrinsic_override=bytes(32))
        self.assertEqual((self.evidence['chains'],self.evidence['transitions'],len(self.evidence['refusals'])),(3,32,3))
