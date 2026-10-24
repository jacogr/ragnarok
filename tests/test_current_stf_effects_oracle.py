# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole-map golden effects, gas, fulfillment and exceptional-selection regression checks."""
import unittest
from current_stf_effects_oracle import (expected_observations, MODES, PAYLOADS, COMMITMENT,
                                        successor, validate_parent, guest_gas, preimage_body,
                                        metadata_parse, metadata_wire, statistics_parse, DEFAULT)
from current_stf_oracle import decode_checkpoint, checkpoint, history
from state_layout_oracle import chapter_key, chapter_service, digest
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire


class CurrentStfEffectsOracle(unittest.TestCase):
    """Frozen original inputs and pinned equations determine every expected successor byte."""

    @classmethod
    def setUpClass(cls):
        """Compute five literal guest chains once without loading any native library or successor capture."""
        cls.lines, cls.evidence = expected_observations()

    def state(self, mode, phase):
        """Select one complete independently generated parent or successor envelope."""
        offset = MODES.index(mode)*5+(0 if phase == 0 else 2*phase)
        return decode_checkpoint(bytes.fromhex(self.lines[offset][2:]))

    def test_frozen_whole_maps_and_second_child(self):
        """Every chain has sixteen globals, current metadata and two actual effect-bearing successors."""
        self.assertEqual(self.evidence['transitions'], 10)
        self.assertEqual(self.evidence['nonempty_extrinsics'], 5)
        self.assertEqual(self.evidence['guest_executions'], 20)
        for mode in MODES:
            original = self.state(mode, 0)
            self.assertTrue({chapter_key(i) for i in range(1, 17)} <= original.keys())
            self.assertNotIn(chapter_key(250), original)
            for phase in (1, 2):
                state = self.state(mode, phase)
                self.assertEqual(int.from_bytes(state[chapter_key(11)], 'little'), phase+1)
                for sid in (42, 99):
                    self.assertEqual(len(state[chapter_service(255, sid)]), 105)
                    self.assertEqual(metadata_parse(state[chapter_service(255, sid)], 105)[2][2],
                                     phase+1)
                blocks, peaks = history(state[chapter_key(3)])
                self.assertEqual(len(blocks), phase+1)
                self.assertEqual([peak is not None for peak in peaks],
                                 [True] if phase == 1 else [False, True])

    def test_storage_footprints_and_exceptional_selection(self):
        """Create, replace, delete and two panic alternatives select exact values and item/octet deltas."""
        expected = {'create': (1, 38), 'replace': (0, -2), 'delete': (-1, -37),
                    'panic-rollback': (0, 0), 'checkpoint-panic': (1, 38)}
        key = value_key('S', 99, b'\7')
        metadata = chapter_service(255, 99)
        for mode, (items, octets) in expected.items():
            original, first, second = (self.state(mode, phase) for phase in (0, 1, 2))
            prior = metadata_parse(original[metadata], 105)
            after = metadata_parse(first[metadata], 105)
            self.assertEqual(after[2][0]-prior[2][0], items)
            self.assertEqual(after[1][4]-prior[1][4], octets)
            self.assertEqual(metadata_parse(second[metadata], 105)[1][4], after[1][4])
            if mode in ('delete', 'panic-rollback'):
                self.assertNotIn(key, first)
            else:
                self.assertEqual(first[key], bytes([9, 8, 7]))
                self.assertEqual(second[key], first[key])
            wanted = b'\0' if mode == 'panic-rollback' else b'\1'+(99).to_bytes(4, 'little')+COMMITMENT
            self.assertEqual(first[chapter_key(16)], wanted)
            self.assertEqual(second[chapter_key(16)], wanted)

    def test_preimages_keep_original_reservations_and_available_slot(self):
        """Two requested extrinsic blobs are fulfilled after execution and retain original slot2 on the next block."""
        for mode in MODES:
            original, first, second = (self.state(mode, phase) for phase in (0, 1, 2))
            for sid, value in PAYLOADS:
                request = request_key(sid, digest(value), len(value))
                preimage = value_key('P', sid, digest(value))
                self.assertEqual(original[request], b'\0')
                self.assertNotIn(preimage, original)
                self.assertEqual(first[preimage], value)
                self.assertEqual(second[preimage], value)
                self.assertEqual(first[request], request_wire((2,)))
                self.assertEqual(second[request], first[request])

    def test_independent_gas_and_provision_statistics(self):
        """Gas is positive even for rolled-back effects; per-block provisions reset while epoch counters accumulate."""
        self.assertEqual({mode: guest_gas(mode) for mode in MODES},
                         {'create': 2650, 'replace': 2650, 'delete': 2649,
                          'panic-rollback': 2650, 'checkpoint-panic': 2754})
        for mode in MODES:
            for phase in (1, 2):
                state = self.state(mode, phase)
                (current, _, cores, services), _ = statistics_parse(state[chapter_key(13)], DEFAULT)
                self.assertEqual(cores, [(0,)*8]*2)
                self.assertEqual([row[-1] for row in services], [22, guest_gas(mode)])
                self.assertEqual([row[1:3] for row in services],
                                 [(1, 1), (1, 1)] if phase == 1 else [(0, 0), (0, 0)])
                self.assertEqual(current[0][:4], (10+phase, 11, 14, 15))

    def test_original_code_and_funding_are_bound(self):
        """Recommitting corrupt code or source metadata cannot select a different reference guest."""
        original = self.state('create', 0)
        key = chapter_service(255, 99)
        code, wide, narrow = metadata_parse(original[key], 105)
        for replacement in (bytes(32), code):
            changed = dict(original)
            balances = list(wide)
            if replacement == code:
                balances[0] = 0
            changed[key] = metadata_wire((replacement, balances, narrow))
            with self.assertRaises(AssertionError):
                validate_parent(changed, 'create')

    def test_semantic_corruption_changes_complete_golden(self):
        """A valid trie root cannot excuse missing fulfillment, wrong gas, timestamp or reverted/retained effects."""
        parent = self.state('checkpoint-panic', 0)
        _, expected = successor(parent, 'checkpoint-panic', PAYLOADS)
        baseline = checkpoint(list(expected.items()))
        keys = [chapter_key(i) for i in (3, 6, 11, 13, 16)]
        keys += [chapter_service(255, 99), value_key('S', 99, b'\7')]
        keys += [request_key(sid, digest(value), len(value)) for sid, value in PAYLOADS]
        keys += [value_key('P', sid, digest(value)) for sid, value in PAYLOADS]
        for key in keys:
            changed = dict(expected)
            changed[key] += b'\xff'
            encoded = checkpoint(list(changed.items()))
            self.assertEqual(decode_checkpoint(encoded), changed)
            self.assertNotEqual(encoded, baseline)

    def test_unsolicited_late_payload_refuses_reference(self):
        """An otherwise ordered late blob cannot borrow the earlier valid item's request."""
        parent = self.state('create', 0)
        with self.assertRaisesRegex(AssertionError, 'preimage not requested'):
            successor(parent, 'create', (PAYLOADS[0], (99, b'Z')))
        for payloads in (tuple(reversed(PAYLOADS)), (PAYLOADS[0], PAYLOADS[0])):
            with self.assertRaisesRegex(AssertionError, 'ordered unique'):
                preimage_body(payloads)
