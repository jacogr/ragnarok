# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Negative controls for restart correlation, immutable registration and bounded byte forwarding.

Exposes RestartValidationTests for unittest discovery; test methods exercise the stated
contracts.
"""
import copy
import hashlib
import io
import json
from pathlib import Path
import unittest
from unittest.mock import Mock

from telemetry_interop_restart import read_frame, verify_registrations, verify_replay
import test_telemetry_interop_validation as interop


# Treat fixture rows as data only; do not inherit or rerun the ordinary interoperability test suite.
class RestartValidationTests(unittest.TestCase):
    def fixture(self):
        """Use nonzero local attempt position and unrelated collector-global IDs across restart."""
        rows, identities = interop.InteropOutputTests().fixture()
        status = copy.deepcopy(rows[0])
        status['node_id'] = identities['client']
        outcome = copy.deepcopy(rows[4])
        outcome['event']['ConnectedOut']['connecting_id'] = 1
        dropped = dict(id=0, node_id=identities['client'], event_type=0,
                       event={'Dropped': dict(timestamp=3, last_timestamp=3, num=5)})
        return [status, rows[2]], [dropped, status, outcome, rows[6]], identities

    def test_original_attempt_survives_prefix(self):
        """The dropped count advances positions without replacing the original connecting ID."""
        before, after, identities = self.fixture()
        self.assertEqual(verify_replay(before, after, identities, 9000),
                         dict(attempt=1, skipped_prefix=5, recovered_events=4))

    def test_wrong_reference_fails(self):
        """Neither a restarted zero counter, a global ID nor the prefix is the pending attempt."""
        for reference in (0, 5, 702):
            # Each wrong namespace must independently fail the same otherwise valid history.
            before, after, identities = self.fixture()
            after[2]['event']['ConnectedOut']['connecting_id'] = reference
            with self.subTest(reference=reference), self.assertRaises(AssertionError):
                verify_replay(before, after, identities, 9000)

    def test_invalid_prefix_fails(self):
        """A prefix must cover every previously observed event and remain bounded."""
        for prefix in (0, 1, 64):
            # Too-short and unbounded prefixes cannot describe this bounded fixture.
            before, after, identities = self.fixture()
            after[0]['event']['Dropped']['num'] = prefix
            with self.subTest(prefix=prefix), self.assertRaises(AssertionError):
                verify_replay(before, after, identities, 9000)

    def test_duplicate_or_lost_outcome_fails(self):
        """Extra success, close, loss markers or replayed attempts cannot hide behind one good close."""
        for index in (0, 2, 3):
            # Each duplicate is individually sufficient to reject the history.
            before, after, identities = self.fixture()
            after.append(copy.deepcopy(after[index]))
            with self.subTest(index=index), self.assertRaises(AssertionError):
                verify_replay(before, after, identities, 9000)
        before, after, identities = self.fixture()
        after.append(before[1])
        with self.assertRaises(AssertionError):
            verify_replay(before, after, identities, 9000)

    def test_wrong_remote_identity_fails(self):
        """The recovered close belongs to the originally pinned remote peer."""
        before, after, identities = self.fixture()
        after[-1]['event']['Disconnected']['peer'] = [7] * 32
        with self.assertRaises(AssertionError):
            verify_replay(before, after, identities, 9000)

    def registration(self):
        """Construct the documented registration prefix using the checked-in chain fixture."""
        chain = json.loads((Path(__file__).parent/'fixtures/telemetry-dev.json').read_text())
        identity = bytes([2] * 32)
        hello = (b'\1' + bytes.fromhex(chain['protocol_parameters']) +
                 hashlib.blake2b(bytes.fromhex(chain['genesis_header']), digest_size=32).digest() +
                 identity + bytes(20))
        return hello, identity.hex(), chain

    def test_registration_identity_and_chain(self):
        """Both identical registrations must still match the configured chain and actual certificate."""
        hello, identity, chain = self.registration()
        verify_registrations([hello.hex()] * 2, identity, chain)
        for index in (1, 123, 155):
            # Matching before/after bytes alone cannot conceal wrong parameters, genesis or identity.
            changed = bytearray(hello)
            changed[index] ^= 1
            with self.subTest(index=index), self.assertRaises(AssertionError):
                verify_registrations([changed.hex()] * 2, identity, chain)
        with self.assertRaises(AssertionError):
            verify_registrations([hello.hex(), (hello + b'\0').hex()], identity, chain)

    def test_frame_bound_and_truncation(self):
        """The relay preserves exact frames and rejects excess allocation or premature EOF."""
        for raw in (b'\0\0\0\0', (2049).to_bytes(4, 'little'), b'\1\0', b'\2\0\0\0x'):
            # A socket-like reader exercises real framing logic without launching a relay thread.
            reader = io.BytesIO(raw)
            with self.subTest(raw=raw), self.assertRaises(AssertionError):
                read_frame(Mock(recv=reader.read))
        reader = io.BytesIO(b'\3\0\0\0abc')
        self.assertEqual(read_frame(Mock(recv=lambda size: reader.read(min(size, 1)))), b'\3\0\0\0abc')
        self.assertIsNone(read_frame(Mock(recv=io.BytesIO().read)))
