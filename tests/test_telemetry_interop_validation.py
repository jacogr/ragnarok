"""Fail-closed validation of the external collector's typed JSON, without launching it."""
import copy
import unittest
from test_telemetry_interop import event_rows, verify


class InteropOutputTests(unittest.TestCase):
    """Independent JSON fixtures distinguish collector-global IDs from per-node JIP-3 positions."""

    def fixture(self):
        """Build two successful lifetimes with an initial server status and unrelated envelope IDs."""
        identities = {'server': bytes([1] * 32).hex(), 'client': bytes([2] * 32).hex()}
        address = {'ipv6': [0] * 10 + [255, 255, 127, 0, 0, 1], 'port': 9000}
        status = dict(timestamp=1, num_peers=0, num_val_peers=0, num_sync_peers=0,
                      num_guarantees=[0, 0], num_shards=0, shards_size=0, num_preimages=0, preimages_size=0)
        rows = []
        # Global WebSocket IDs deliberately differ from every valid connecting_id.
        def event(role, tag, variant, fields):
            rows.append(dict(id=700 + len(rows), node_id=identities[role], event_type=tag,
                             event={variant: dict(timestamp=1, **fields)}))
        event('server', 10, 'Status', {key: value for key, value in status.items() if key != 'timestamp'})
        event('server', 21, 'ConnectingIn', {'from': address})
        event('client', 24, 'ConnectingOut', {'to': {'peer_id': [1] * 32, 'peer_address': address}})
        event('server', 23, 'ConnectedIn', {'connecting_id': 1, 'peer_id': [2] * 32})
        event('client', 26, 'ConnectedOut', {'connecting_id': 0})
        event('server', 27, 'Disconnected', {'peer': [2] * 32, 'terminator': None, 'reason': ''})
        event('client', 27, 'Disconnected', {'peer': [1] * 32, 'terminator': None, 'reason': ''})
        return rows, identities

    def test_local_positions_ignore_global_ids(self):
        """A status advances the server's position; events from the other node do not."""
        rows, identities = self.fixture()
        self.assertEqual(verify(rows, identities, 9000), {'server': 4, 'client': 3})

    def test_global_id_is_not_a_correlation_id(self):
        """Mistaking the WebSocket envelope ID for the wire attempt ID fails verification."""
        rows, identities = self.fixture()
        rows[3]['event']['ConnectedIn']['connecting_id'] = rows[1]['id']
        with self.assertRaises(AssertionError):
            verify(rows, identities, 9000)

    def test_duplicate_close_fails(self):
        """Extra terminal events cannot be hidden by the collector history snapshot."""
        rows, identities = self.fixture()
        rows.append(copy.deepcopy(rows[-1]))
        with self.assertRaises(AssertionError):
            verify(rows, identities, 9000)

    def test_wrong_core_count_fails(self):
        """The status array must reflect the chain's decoded two-core parameters."""
        rows, identities = self.fixture()
        rows[0]['event']['Status']['num_guarantees'] = []
        with self.assertRaises(AssertionError):
            verify(rows, identities, 9000)

    def test_wrong_authenticated_identity_fails(self):
        """A successful decode cannot conceal a different authenticated remote identity."""
        rows, identities = self.fixture()
        rows[3]['event']['ConnectedIn']['peer_id'] = [9] * 32
        with self.assertRaises(AssertionError):
            verify(rows, identities, 9000)

    def test_dropped_observations_fail(self):
        """This complete-lifecycle case requires every event, even if a collector accepts a loss marker."""
        rows, identities = self.fixture()
        rows.insert(1, dict(node_id=identities['server'], event_type=0,
                            event={'Dropped': dict(timestamp=1, last_timestamp=1, num=1)}))
        with self.assertRaises(AssertionError):
            verify(rows, identities, 9000)


class CollectorBatchTests(unittest.TestCase):
    """The collector's scheduling-dependent batching must not lose otherwise valid observations."""

    def test_batch_preserves_order(self):
        """Single-event and batched envelopes expose exactly the same ordered records."""
        first, second = {'id': 7}, {'id': 8}
        batch = {'type': 'batch', 'data': [{'type': 'event', 'data': first},
                                         {'type': 'event', 'data': second}]}
        self.assertEqual(event_rows(batch), [first, second])
        self.assertEqual(event_rows({'type': 'event', 'data': first}), [first])
        self.assertEqual(event_rows({'type': 'stats', 'data': {}}), [])

    def test_invalid_batch_fails(self):
        """Empty, oversized and nested/control batches are not silently skipped."""
        for rows in ([], [{'type': 'event', 'data': {}}] * 65, [{'type': 'stats'}]):
            with self.subTest(rows=len(rows)), self.assertRaises(AssertionError):
                event_rows({'type': 'batch', 'data': rows})
