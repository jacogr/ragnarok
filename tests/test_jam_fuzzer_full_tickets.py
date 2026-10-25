# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent ticket algebra checks guard full-profile batch limits, ordering, disjointness and complete maps."""
import unittest
import jam_fuzzer_full_tickets_oracle as reference
import jam_fuzzer_full_guests_oracle as guests
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key
from state_statistics_oracle import parse as statistics_parse


class FullTicketAdmission(unittest.TestCase):
    """Calculate the complete reference once; no native client constructs an expected state."""

    @classmethod
    def setUpClass(cls):
        """Retain independent complete maps for both maximal-batch partition orders."""
        _,cls.lines,cls.evidence = reference.expected_observations()
        cls.bank = reference.bank()

    def test_complete_contests_and_statistics(self):
        """Both paths retain every one of20 distinct scores and account for all submissions at actual author indices."""
        chain = []
        # Every emitted state is independently decoded and recommitted before comparing semantic contents.
        for line in self.lines:
            tag,data = line.split(' ',1)
            if tag == 'P': chain = [decode_checkpoint(bytes.fromhex(data))]
            elif tag == 'O':
                state = decode_checkpoint(bytes.fromhex(data));chain.append(state)
                pending,_,kind,schedule,accumulated = reference.consensus(state[chapter_key(4)])
                self.assertEqual((len(pending),kind,len(schedule)),(1023,1,600))
                self.assertEqual(len(set(row[:32] for row in accumulated)),len(accumulated))
                stats,_ = statistics_parse(state[chapter_key(13)],(341,1023,1023,2**64-1,2**64-1))
                before,_ = statistics_parse(chain[0][chapter_key(13)],(341,1023,1023,2**64-1,2**64-1))
                self.assertEqual(sum(row[1] for row in stats[0])-sum(row[1] for row in before[0]),len(accumulated))
                # Ticket admission cannot alter either complete guest service namespace.
                for key,value in chain[0].items():
                    if key[0] == 255: self.assertEqual(state[key],value)
        self.assertEqual(self.evidence['transitions'],6)

    def test_strict_batch_order(self):
        """Two individually valid membership proofs in reverse score order cannot form an accepted batch."""
        with self.assertRaisesRegex(AssertionError,'ticket order'):
            reference.successor(guests.original('create'),2,list(reversed(self.bank[:2])))

    def test_full_limit_and_attempt_domain(self):
        """The17th ticket and attempt2 are illegal under canonical full GP parameters."""
        parent = guests.original('create')
        with self.assertRaisesRegex(AssertionError,'ticket window'): reference.successor(parent,2,self.bank[:17])
        row = dict(self.bank[0],attempt=2)
        with self.assertRaisesRegex(AssertionError,'attempt domain'): reference.successor(parent,2,[row])

    def test_prior_duplicate_and_tail(self):
        """Prior membership is identifier-based and the500-slot tail forbids even one otherwise valid ticket."""
        _,parent = reference.successor(guests.original('create'),2,self.bank[:1])
        with self.assertRaisesRegex(AssertionError,'duplicate ticket'): reference.successor(parent,3,self.bank[:1])
        with self.assertRaisesRegex(AssertionError,'ticket window'): reference.successor(parent,500,self.bank[1:2])
