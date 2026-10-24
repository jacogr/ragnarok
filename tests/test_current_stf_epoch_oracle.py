# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Freeze independent epoch, ticket, marker, entropy and whole-map invariants for complete authored chains."""
import copy
import json
import unittest
from current_stf_epoch_oracle import (FIXTURE, NAMES, SLOTS, expected_observations, bank_records,
                                      consensus, roster, submitted_for, successor, zigzag, PUBLIC)
from current_stf_oracle import Reader, decode_checkpoint
from state_layout_oracle import chapter_key
from state_statistics_oracle import parse as statistics_parse, DEFAULT


def header_parts(child):
    """Independently inspect marker/author extents without fixed offsets after optional markers."""
    source = Reader(child)
    source.take(100)
    epoch = None
    tag = source.take(1)
    if tag == b'\1':
        eta0, eta1 = source.take(32), source.take(32)
        records = [source.take(64) for _ in range(source.count())]
        epoch = (eta0, eta1, records)
    else:
        assert tag == b'\0'
    winners = None
    tag = source.take(1)
    if tag == b'\1':
        winners = [source.take(33) for _ in range(12)]
    else:
        assert tag == b'\0'
    author = int.from_bytes(source.take(2), 'little')
    source.take(96)
    assert source.count() == 0
    source.take(96)
    return epoch, winners, author, source.at


class CurrentStfEpochOracle(unittest.TestCase):
    """These references compute complete expected successors and credentials without any native library."""

    @classmethod
    def setUpClass(cls):
        """Share one independent calculation of the frozen three-chain corpus across focused invariants."""
        cls.requests, cls.lines, cls.evidence = expected_observations()
        cls.fixture = json.loads(FIXTURE.read_text())
        cls.bank = bank_records(cls.fixture)
        cls.states, cls.children = [], []
        cursor = 0
        for slots in SLOTS:
            states = [decode_checkpoint(bytes.fromhex(cls.lines[cursor][2:]))]
            children = []
            cursor += 1
            for _ in slots:
                children.append(bytes.fromhex(cls.lines[cursor][2:]))
                states.append(decode_checkpoint(bytes.fromhex(cls.lines[cursor+1][2:])))
                cursor += 2
            cls.states.append(states)
            cls.children.append(children)
        assert cursor == len(cls.lines)

    def test_contests_and_crossing_reset(self):
        """All scores are admitted in order, a full contest saturates, and crossing retains only new tickets."""
        self.assertEqual(self.evidence['transitions'], 22)
        self.assertEqual(len(self.requests), 14)
        for case, slots in enumerate(SLOTS):
            for index, slot in enumerate(slots):
                current = consensus(self.states[case][index+1][chapter_key(4)])
                accumulated = current[4]
                if slot in (2, 3, 4, 5):
                    self.assertEqual(len(accumulated), (slot-1)*3)
                elif slot in (10, 11):
                    self.assertEqual(len(accumulated), 12 if case == 0 else 6)
                elif slot == 12:
                    self.assertEqual(accumulated, [bytes.fromhex(self.bank[12]['score'])+b'\2'])
                elif slot == 13:
                    self.assertEqual(len(accumulated), 2)
                else:
                    self.assertEqual(accumulated, [])

    def test_ticket_schedule_and_two_fallback_causes(self):
        """Only adjacent crossing from a saturated tail selects tickets; skipped/incomplete tail selects hashed keys."""
        for case, slots in enumerate(SLOTS):
            at = slots.index(12)
            prior = consensus(self.states[case][at][chapter_key(4)])
            current = consensus(self.states[case][at+1][chapter_key(4)])
            if case == 0:
                self.assertEqual(current[2], 0)
                self.assertEqual(current[3], zigzag(prior[4]))
            else:
                self.assertEqual(current[2], 1)
                self.assertTrue(all(key in PUBLIC for key in current[3]))
        before = self.states[0][SLOTS[0].index(36)]
        after = self.states[0][SLOTS[0].index(36)+1]
        self.assertEqual(consensus(after[chapter_key(4)])[2], 1)
        self.assertEqual(after[chapter_key(6)][32:], before[chapter_key(6)][:96])

    def test_roster_roles_markers_and_author_positions(self):
        """Epoch markers name new pending keys, active rotates from old pending, and every author uses the new active ordinal."""
        authors = set()
        for case, slots in enumerate(SLOTS):
            for index, slot in enumerate(slots):
                before, after = self.states[case][index:index+2]
                epoch, winners, author, size = header_parts(self.children[case][index])
                authors.add(author)
                previous = int.from_bytes(before[chapter_key(11)], 'little')
                crossed = slot//12 > previous//12
                self.assertEqual(epoch is not None, crossed)
                if crossed:
                    self.assertEqual(roster(after[chapter_key(8)]), consensus(before[chapter_key(4)])[0])
                    self.assertEqual(after[chapter_key(9)], before[chapter_key(8)])
                    self.assertEqual(consensus(after[chapter_key(4)])[0], roster(before[chapter_key(7)]))
                    self.assertEqual(epoch[:2], (before[chapter_key(6)][:32], before[chapter_key(6)][32:64]))
                    self.assertEqual(epoch[2], [record[:64] for record in roster(before[chapter_key(7)])])
                self.assertEqual(winners is not None, case == 0 and slot == 10)
                if winners is not None:
                    self.assertEqual(winners, zigzag(consensus(before[chapter_key(4)])[4]))
                self.assertGreaterEqual(size, 297)
        self.assertGreaterEqual(len(authors), 4)

    def test_statistics_rotation_and_no_unrelated_map_changes(self):
        """Current/previous epoch arrays rotate once even across skipped epochs; services and unmodified globals remain exact."""
        for case, slots in enumerate(SLOTS):
            for index, slot in enumerate(slots):
                before, after = self.states[case][index:index+2]
                previous = int.from_bytes(before[chapter_key(11)], 'little')
                (old_current, old_previous, _, _), _ = statistics_parse(before[chapter_key(13)], DEFAULT)
                (current, past, cores, services), _ = statistics_parse(after[chapter_key(13)], DEFAULT)
                count = len(submitted_for(slot, self.bank))
                if slot//12 > previous//12:
                    self.assertEqual(past, old_current)
                    self.assertEqual(sum(row[0] for row in current), 1)
                    self.assertEqual(sum(row[1] for row in current), count)
                else:
                    self.assertEqual(past, old_previous)
                    self.assertEqual(sum(row[0] for row in current), sum(row[0] for row in old_current)+1)
                    self.assertEqual(sum(row[1] for row in current), sum(row[1] for row in old_current)+count)
                self.assertEqual((cores, services), ([(0,)*8]*2, []))
                unchanged = set(before)-{chapter_key(i) for i in (1, 3, 4, 6, 8, 9, 11, 13)}
                self.assertTrue(all(before[key] == after[key] for key in unchanged))

    def test_ticket_order_attempt_window_duplicate_and_ring_domains(self):
        """Independent admission equations reject the same explicit protocol-domain failures as the native controls."""
        parent = self.states[0][0]
        roots = dict(pending=consensus(parent[chapter_key(4)])[1], staging=bytes.fromhex(self.fixture['staging_ring_root']))
        invalid = copy.deepcopy(self.bank[0])
        invalid['attempt'] = 4
        probes = ((parent, 2, [invalid], 'attempt domain'),
                  (parent, 2, [self.bank[1], self.bank[0]], 'ticket order'),
                  (self.states[0][1], 3, [self.bank[0]], 'duplicate ticket'),
                  (self.states[0][4], 10, [self.bank[0]], 'ticket window'),
                  (self.states[0][6], 12, [self.bank[0]], 'ring domain'))
        for state, slot, submitted, reason in probes:
            with self.assertRaisesRegex(AssertionError, reason):
                successor(state, slot, submitted, self.bank, roots)

    def test_fixed_ring_O_and_score_attribution(self):
        """Proof witnesses cannot be relabeled with another scalar, attempt or score while keeping the golden inputs."""
        for field, value in (('secret', 7), ('attempt', 4), ('score', bytes(32).hex())):
            changed = copy.deepcopy(self.fixture)
            changed['ticket_bank'][0][field] = value
            with self.assertRaises(AssertionError):
                bank_records(changed)
