# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Focused independent invariants for whole-map offenders, changing populations and ticket eviction."""
import copy
import json
import unittest
import current_stf_population_oracle as population
import current_stf_eviction_oracle as eviction
from current_stf_epoch_oracle import consensus, roster, successor, NULL_VALIDATOR, zigzag
from current_stf_oracle import decode_checkpoint, Reader
from state_layout_oracle import chapter_key
from state_statistics_oracle import parse as statistics_parse, DEFAULT


def observations(lines):
    """Separate exact independently authored block bytes from original and calculated whole maps."""
    states = [decode_checkpoint(bytes.fromhex(line[2:])) for line in lines if line.startswith(('P ', 'O '))]
    blocks = [bytes.fromhex(line[2:]) for line in lines if line.startswith('B ')]
    assert len(states) == len(blocks)+1
    return states, blocks


def marker(block):
    """Read variable epoch/winner and offender extents without borrowing a native parser."""
    reader = Reader(block)
    reader.take(100)
    epoch = None
    if reader.take(1) == b'\1':
        reader.take(64)
        epoch = [reader.take(64) for _ in range(reader.count())]
    winners = None
    if reader.take(1) == b'\1':
        winners = [reader.take(33) for _ in range(12)]
    author = int.from_bytes(reader.take(2), 'little')
    reader.take(96)
    offenders = [reader.take(32) for _ in range(reader.count())]
    return epoch, winners, author, offenders


class CurrentStfPopulationOracle(unittest.TestCase):
    """No native library or observed successor participates in these calculations."""

    @classmethod
    def setUpClass(cls):
        """Calculate each whole-map chain once, then inspect separate protocol invariants."""
        lines, cls.evidence = population.expected_observations()
        cls.states, cls.blocks = observations(lines)
        cls.requests, lines, cls.eviction_evidence = eviction.expected_observations()
        cls.contests, cls.ticket_blocks = observations(lines)

    def test_live_offender_marker_and_deferred_full_null_record(self):
        """Culprit evidence changes C5 immediately; only the crossing filters pending full336-byte records."""
        _, offender = population.evidence(self.states[0])
        self.assertEqual(self.states[1][chapter_key(5)], b'\0\1'+bytes(32)+b'\0\1'+offender)
        for index, slot in enumerate(population.SLOTS):
            state = self.states[index+1]
            pending = consensus(state[chapter_key(4)])[0]
            original_staging = roster(self.states[0][chapter_key(7)])
            self.assertEqual(state[chapter_key(7)], self.states[0][chapter_key(7)])
            self.assertEqual(marker(self.blocks[index])[3], [offender] if slot == 2 else [])
            if slot < 12:
                self.assertTrue(any(row[32:64] == offender for row in pending))
            else:
                self.assertEqual(pending, [NULL_VALIDATOR]+original_staging[1:])
                self.assertEqual(pending[0], bytes(32)+b'\2'+bytes(303))
                self.assertEqual(marker(self.blocks[index])[0], [row[:64] for row in pending]
                                 if slot in (12, 24) else None)
        self.assertTrue(all(octet for octet in original_staging[0][64:]))
        self.assertTrue(all(state[chapter_key(5)] == self.states[1][chapter_key(5)] for state in self.states[1:]))

    def test_all_roster_roles_and_statistics_resize_independently(self):
        """Actual active/current and previous counters rotate6/9→9/6→6/9 without truncating full records."""
        for index, slot in enumerate(population.SLOTS):
            before, after = self.states[index:index+2]
            current_count, previous_count = (len(roster(after[chapter_key(chapter)])) for chapter in (8, 9))
            expected = (6, 9) if slot < 12 or slot >= 24 else (9, 6)
            self.assertEqual((current_count, previous_count), expected)
            config = (3, current_count, previous_count, *DEFAULT[3:])
            (current, previous, cores, services), consumed = statistics_parse(after[chapter_key(13)], config)
            self.assertEqual(consumed, len(after[chapter_key(13)]))
            self.assertEqual((len(current), len(previous)), expected)
            self.assertEqual((cores, services), ([(0,)*8]*3, []))
            if slot in (12, 24):
                self.assertEqual(roster(after[chapter_key(8)]), consensus(before[chapter_key(4)])[0])
                self.assertEqual(after[chapter_key(9)], before[chapter_key(8)])
                self.assertEqual(sum(row[0] for row in current), 1)
            unchanged = set(before)-{chapter_key(i) for i in (1, 3, 4, 5, 6, 8, 9, 11, 13)}
            self.assertTrue(all(before[key] == after[key] for key in unchanged))

    def test_null_fallback_slots_remain_unsealable(self):
        """An offender's null active key can occupy fallback slots; no positive secret signs that selected key."""
        schedule = consensus(self.states[-1][chapter_key(4)])[3]
        self.assertEqual([24+i for i, key in enumerate(schedule) if key == bytes(32)], [28, 32, 33])
        roots = dict(staging=consensus(self.states[-1][chapter_key(4)])[1])
        with self.assertRaises(KeyError):
            successor(self.states[-1], 28, [], [], roots, cores=3)

    def test_top_twelve_eviction_and_winner_selected_for_sealing(self):
        """Exactly the former worst ticket disappears, and the new best id/attempt wins the slot12 seal."""
        fixture = json.loads(eviction.FIXTURE.read_text())
        _, bank = eviction.inputs(fixture)
        before = consensus(self.contests[4][chapter_key(4)])[4]
        after = consensus(self.contests[5][chapter_key(4)])[4]
        incoming = bytes.fromhex(bank[14]['score'])+b'\3'
        self.assertEqual(after, sorted(before+[incoming])[:12])
        self.assertEqual(set(before)-set(after), {bytes.fromhex(bank[11]['score'])+b'\1'})
        self.assertEqual(after[0], incoming)
        self.assertEqual(marker(self.ticket_blocks[6])[1], zigzag(after))
        self.assertEqual(consensus(self.contests[9][chapter_key(4)])[2:4], (0, zigzag(after)))
        self.assertEqual(zigzag(after)[0], incoming)
        self.assertEqual(marker(self.ticket_blocks[8])[2], 5)  # scalar1's new pending→active ordinal.

    def test_valid_but_unretained_inputs_and_relabelled_proofs(self):
        """Fresh high-score and evicted inputs both fail retention; scalar/attempt attribution cannot be relabelled."""
        fixture = json.loads(eviction.FIXTURE.read_text())
        prior, bank = eviction.inputs(fixture)
        roots = dict(pending=consensus(self.contests[0][chapter_key(4)])[1])
        for item in (bank[15], bank[11]):
            with self.assertRaisesRegex(AssertionError, 'ticket not retained'):
                successor(self.contests[5], 7, [item], bank, roots)
        changed = copy.deepcopy(fixture)
        changed['extra_tickets'][0]['secret'] = 2
        with self.assertRaises(AssertionError):
            eviction.inputs(changed)
        self.assertEqual((self.evidence['transitions'], self.eviction_evidence['transitions']), (6, 10))
        self.assertEqual(len(self.requests), 16)
