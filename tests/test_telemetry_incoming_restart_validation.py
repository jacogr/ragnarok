# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent collector JSON fixtures for incoming replay and listener generation isolation."""
import copy
import unittest
from telemetry_interop_incoming import verify_incoming


# Keep global collector IDs unrelated to local positions, including statuses on both sides of restart.
class IncomingRestartValidationTests(unittest.TestCase):
    def fixture(self, rejected=False):
        """Create one covered attempt and a fresh post-restart generation with a different identity."""
        server = bytes([1] * 32).hex()
        clients = [bytes([2] * 32).hex(), bytes([3] * 32).hex()]
        ports = [9000, 9001]
        status = dict(num_peers=0, num_val_peers=0, num_sync_peers=0, num_guarantees=[0, 0],
                      num_shards=0, shards_size=0, num_preimages=0, preimages_size=0)

        # Handwritten variants are intentionally independent of production wire encoding.
        def event(tag, variant, **fields):
            return dict(id=700, node_id=server, event_type=tag, event={variant: dict(timestamp=1, **fields)})

        # Incoming addresses must identify the corresponding generation's actual relay endpoint.
        def address(port):
            return {'from': {'ipv6': [0] * 10 + [255, 255, 127, 0, 0, 1], 'port': port}}

        before = [event(10, 'Status', **status), event(21, 'ConnectingIn', **address(ports[0]))]
        after = [event(0, 'Dropped', last_timestamp=1, num=7), event(10, 'Status', **status)]
        if rejected:
            # Rejection settles the old ID but has no authenticated identity or close.
            after.append(event(22, 'ConnectInFailed', connecting_id=1, reason=''))
        else:
            # Success carries the first client's identity through authentication and retirement.
            after.extend([event(23, 'ConnectedIn', connecting_id=1, peer_id=[2] * 32),
                          event(27, 'Disconnected', peer=[2] * 32, terminator=None, reason='')])
        fresh = 7 + len(after) - 1
        after.extend([event(21, 'ConnectingIn', **address(ports[1])),
                      event(23, 'ConnectedIn', connecting_id=fresh, peer_id=[3] * 32),
                      event(27, 'Disconnected', peer=[3] * 32, terminator=None, reason='')])
        return before, after, server, clients, ports, rejected

    def test_both_outcomes_and_fresh_generation(self):
        """Both terminal kinds retain the old ID and assign a distinct correctly advanced new one."""
        for rejected in (False, True):
            # The missing rejection close changes the new attempt's local position by one.
            with self.subTest(rejected=rejected):
                result = verify_incoming(*self.fixture(rejected))
                self.assertEqual(result['attempts'], [1, 9 if rejected else 10])
                self.assertEqual(result['closes'], 1 if rejected else 2)

    def test_old_id_cannot_leak_into_new_generation(self):
        """An otherwise correct fresh authentication must not settle the covered first attempt."""
        for rejected in (False, True):
            # Both success and rejection release the previous correlation state before listener reuse.
            data = self.fixture(rejected)
            data[1][-2]['event']['ConnectedIn']['connecting_id'] = 1
            with self.subTest(rejected=rejected), self.assertRaises(AssertionError):
                verify_incoming(*data)

    def test_prefix_is_not_an_extra_event(self):
        """Counting the dropped marker as one event shifts the fresh ID and must fail."""
        data = self.fixture()
        data[1][-2]['event']['ConnectedIn']['connecting_id'] += 1
        with self.assertRaises(AssertionError):
            verify_incoming(*data)

    def test_rejection_cannot_close(self):
        """An extra authenticated close cannot substitute for or follow the rejected generation."""
        data = self.fixture(True)
        data[1].insert(3, copy.deepcopy(data[1][-1]))
        with self.assertRaises(AssertionError):
            verify_incoming(*data)

    def test_stale_identity_and_endpoint_fail(self):
        """Correct tags and correlation IDs cannot hide metadata from the preceding connection."""
        for field in ('identity', 'endpoint'):
            # Mutate one independent ownership signal at a time.
            data = self.fixture()
            if field == 'identity':
                data[1][-1]['event']['Disconnected']['peer'] = [2] * 32
            else:
                data[1][-3]['event']['ConnectingIn']['from']['port'] = 9000
            with self.subTest(field=field), self.assertRaises(AssertionError):
                verify_incoming(*data)

    def test_duplicate_outcome_and_short_prefix_fail(self):
        """Lost history cannot be hidden by a short prefix or duplicate terminal callback."""
        data = self.fixture()
        data[1].append(copy.deepcopy(data[1][-2]))
        with self.assertRaises(AssertionError):
            verify_incoming(*data)
        data = self.fixture()
        data[1][0]['event']['Dropped']['num'] = 1
        with self.assertRaises(AssertionError):
            verify_incoming(*data)

    def test_rejection_reason_and_old_reference_fail(self):
        """A fabricated reason or collector-global attempt ID invalidates the rejected outcome."""
        for field, value in (('reason', 'invented'), ('connecting_id', 700)):
            # The public collector envelope ID is deliberately distinct from every valid local reference.
            data = self.fixture(True)
            data[1][2]['event']['ConnectInFailed'][field] = value
            with self.subTest(field=field), self.assertRaises(AssertionError):
                verify_incoming(*data)
