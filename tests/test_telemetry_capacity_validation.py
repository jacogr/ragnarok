# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent collector JSON verdict tests for capacity refusal and slot recovery.

Exposes CapacityValidationTests for unittest discovery; test methods exercise the stated
contracts.
"""
import copy
import unittest
from telemetry_interop_capacity import verify_capacity


# Distinct identities separate a refused TLS peer from the released holder and successful replacement.
class CapacityValidationTests(unittest.TestCase):
    def fixture(self):
        """Construct status-interleaved local attempt positions with unrelated global envelope IDs."""
        identities = {role: bytes([index] * 32).hex() for index, role in
                      enumerate(('server', 'held', 'refused', 'recovered'), 1)}
        rows = []

        # Fixed collector IDs deliberately cannot stand in for the implicit JIP-3 position.
        def event(tag, variant, **fields):
            rows.append(dict(id=999, node_id=identities['server'], event_type=tag,
                             event={variant: dict(timestamp=1, **fields)}))

        # Status consumes a local event ID even though it is absent from the lifecycle sequence.
        def status(peers):
            event(10, 'Status', num_peers=peers, num_val_peers=0, num_sync_peers=0, num_guarantees=[0, 0],
                  num_shards=0, shards_size=0, num_preimages=0, preimages_size=0)

        # Authentication precedes capacity admission, so the refused peer also has a success callback.
        def attempt(index, role):
            address = dict(ipv6=[0] * 15 + [1], port=9000 + index)
            position = len(rows)
            event(21, 'ConnectingIn', **{'from': address})
            status(min(index, 16))
            event(23, 'ConnectedIn', connecting_id=position, peer_id=list(bytes.fromhex(identities[role])))
            return address

        # A sixteen-connection fill is followed by one excess attempt and exactly one admission refusal.
        for index in range(16):
            attempt(index, 'held')
        refused = attempt(16, 'refused')
        event(20, 'ConnectionRefused', **{'from': copy.deepcopy(refused)})
        event(27, 'Disconnected', peer=list(bytes.fromhex(identities['held'])), terminator=None, reason='')
        attempt(17, 'recovered')
        event(27, 'Disconnected', peer=list(bytes.fromhex(identities['recovered'])), terminator=None, reason='')
        status(15)
        return rows, identities

    def test_complete_capacity_lifetime(self):
        """The complete history retains all eighteen attempt IDs and only two admitted-peer closes."""
        self.assertEqual(verify_capacity(*self.fixture()), dict(attempts=18, authenticated=18,
                         refused=1, admitted=17, observed_closes=2))

    def test_wrong_refusal_endpoint(self):
        """Refusing an address from an admitted attempt is not equivalent to rejecting the excess peer."""
        rows, identities = self.fixture()
        refusal = next(row for row in rows if row['event_type'] == 20)
        refusal['event']['ConnectionRefused']['from']['port'] = 9000
        with self.assertRaises(AssertionError):
            verify_capacity(rows, identities)

    def test_refused_peer_cannot_close(self):
        """A TLS-successful but unadmitted peer has no admitted-peer disconnect."""
        rows, identities = self.fixture()
        rows[-2]['event']['Disconnected']['peer'] = list(bytes.fromhex(identities['refused']))
        with self.assertRaises(AssertionError):
            verify_capacity(rows, identities)

    def test_global_reference_fails(self):
        """Collector-global IDs cannot correlate incoming success with the local start position."""
        rows, identities = self.fixture()
        rows[2]['event']['ConnectedIn']['connecting_id'] = 999
        with self.assertRaises(AssertionError):
            verify_capacity(rows, identities)

    def test_extra_refusal_fails(self):
        """A duplicate refusal cannot be hidden by successful recovery later in the history."""
        rows, identities = self.fixture()
        rows.append(copy.deepcopy(next(row for row in rows if row['event_type'] == 20)))
        with self.assertRaises(AssertionError):
            verify_capacity(rows, identities)

    def test_excess_peer_is_not_counted(self):
        """Periodic status must not count the refused connection as a seventeenth admitted peer."""
        rows, identities = self.fixture()
        rows[1]['event']['Status']['num_peers'] = 17
        with self.assertRaises(AssertionError):
            verify_capacity(rows, identities)

    def test_recovery_identity_is_fresh(self):
        """The replacement's authentication cannot reuse the excess peer's identity."""
        rows, identities = self.fixture()
        rows[-3]['event']['ConnectedIn']['peer_id'] = list(bytes.fromhex(identities['refused']))
        with self.assertRaises(AssertionError):
            verify_capacity(rows, identities)
