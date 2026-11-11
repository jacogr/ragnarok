# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent acceptance must reject changed maps and journals even when reported heads agree."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from tiny_devnet_checks import check, smoke, authoring, freeze
from tiny_devnet import exercise, free_ports
from tiny_devnet_oracle import verify


class TinyDevnetEvidence(unittest.TestCase):
    """Small inert observations exercise acceptance predicates without duplicating the live E2E workload."""

    def test_short_ci_retains_independent_checks(self):
        """The CI-sized run uses two real slots and both independent verification callbacks."""
        for selected,slots,restart,late in ((smoke,2,False,False),(check,14,True,False),(authoring,3,False,True)):
            with self.subTest(slots=slots), patch('tiny_devnet_checks.exercise', return_value={'passed':True}) as run:
                self.assertTrue(selected(Path('/binary'),Path('/unused'))['passed'])
                self.assertEqual(run.call_args.kwargs['slots'], slots)
                self.assertEqual(run.call_args.kwargs['restart'], restart)
                self.assertEqual(run.call_args.kwargs.get('late_join',False), late)
                self.assertIs(run.call_args.kwargs['before_start'],freeze)
                self.assertIs(run.call_args.kwargs['after_stop'],verify)

    def test_restart_requires_the_full_horizon(self):
        """A short smoke cannot silently claim epoch or restart coverage."""
        with self.assertRaisesRegex(ValueError,'at least13'):
            exercise(Path('/binary'),Path('/unused'),slots=2,restart=True)

    def test_late_author_requires_a_separate_three_slot_lifetime(self):
        """Cold eligible authoring cannot silently reuse smoke or restart coverage."""
        for slots,restart in ((2,False),(14,True)):
            with self.subTest(slots=slots), self.assertRaisesRegex(ValueError,'Late author acceptance'):
                exercise(Path('/binary'),Path('/unused'),slots=slots,restart=restart,late_join=True)

    def test_listener_block_avoids_automatic_and_occupied_ports(self):
        """A blocked low block must leave only the complete high block available."""
        occupied = {1027}

        class Reservation:
            """Track live UDP reservations without depending on host networking."""

            port = None

            def bind(self, address):
                """Model both explicit binds and the old automatic bind request."""
                host, requested = address
                assert host == '127.0.0.1'
                selected = requested or 43834
                if selected in occupied:
                    raise OSError('UDP port already held')
                occupied.add(selected)
                self.port = selected

            def getsockname(self):
                """Expose the bound address for the automatic allocation control."""
                return '127.0.0.1', self.port

            def close(self):
                """Release only ports this reservation actually acquired."""
                if self.port is not None:
                    occupied.remove(self.port)

        with patch('tiny_devnet.automatic_port_range', return_value=(1030, 65529)), patch(
                'tiny_devnet.random.sample', return_value=[0, 1]), patch(
                'tiny_devnet.socket.socket', side_effect=lambda *_: Reservation()):
            self.assertEqual(free_ports(), 65530)
        self.assertEqual(occupied, {1027})

    def observations(self, directory):
        """Create equal reported roots with explicit test-owned map and journal identities."""
        expected = dict(states=[b'initial-map',b'successor-map'],blocks=[b'signed-input'],
                        roots=['initial-root','successor-root'])
        for index in range(6):
            folder = directory/f'node-{index}'
            folder.mkdir()
            for slot,state in enumerate(expected['states']):
                (folder/f'state-{slot}.bin').write_bytes(state)
            (folder/'state.bin').write_bytes(expected['states'][-1])
            block = expected['blocks'][0]
            (folder/'blocks.bin').write_bytes(len(block).to_bytes(4,'little')+block)
            (folder/'stdout.log').write_text(''.join(
                f'DEVNET_BLOCK node={index} source=peer slot={slot} hash=reported root={root}\n'
                for slot,root in enumerate(expected['roots'])))
        return expected

    def test_equal_roots_do_not_replace_whole_map_comparison(self):
        """A stale/corrupt checkpoint at any node must fail despite unchanged convergence logs."""
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            expected = self.observations(directory)
            self.assertTrue(verify(directory,1,expected)['independent'])
            (directory/'node-4/state-0.bin').write_bytes(b'changed-map')
            with self.assertRaisesRegex(AssertionError,'whole-map mismatch'):
                verify(directory,1,expected)

    def test_journal_must_match_independent_signed_inputs(self):
        """Equal complete checkpoints cannot conceal different or truncated replay authority."""
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            expected = self.observations(directory)
            (directory/'node-2/blocks.bin').write_bytes(b'truncated')
            with self.assertRaisesRegex(AssertionError,'journal differs'):
                verify(directory,1,expected)

    def test_last_checkpoint_is_not_a_complete_trace(self):
        """Removing an intermediate observation must fail instead of accepting the final map alone."""
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            expected = self.observations(directory)
            (directory/'node-3/state-0.bin').unlink()
            with self.assertRaises(FileNotFoundError):
                verify(directory,1,expected)


if __name__ == '__main__':
    unittest.main()
