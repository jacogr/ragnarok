# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Strict continuing frame/state/host parity and intended mutation refusal; actual DOOM runs only on native CI."""
import copy
from pathlib import Path
import sys
import re
import subprocess
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from pvm_doom_backends import Mismatch, compare, negative_frames, rgba_frames
from workflow_fixtures import event_context, expression, job_condition, job_section

ROOT = Path(__file__).resolve().parents[1]


def events(pixel=0):
    """Use a full real-size host frame with an independently chosen BGRX pixel."""
    raw = bytes((pixel, 2, 3, 0))*(640*400)
    return b'\x01'+len(raw).to_bytes(4, 'little')+raw


def observed():
    """Model already executed receipts with distinct adjacent frames and complete independent call identities."""
    return dict(frames=rgba_frames(events(1), 0, 0)+rgba_frames(events(2), 1, 1),
        calls=[dict(state_sha256='state'+str(i), events_sha256='events'+str(i),
                    hosts_sha256='hosts'+str(i), gas=100-i) for i in range(2)])


class DoomBackendTests(unittest.TestCase):
    def test_every_frame_order_state_and_host_stream_is_required(self):
        """A matching final frame cannot excuse a changed earlier frame, CPU/page state or ordered host stream."""
        wanted = observed()
        compare(wanted, copy.deepcopy(wanted), 2)
        for field in ('state_sha256', 'events_sha256', 'hosts_sha256', 'gas'):
            changed = copy.deepcopy(wanted)
            changed['calls'][0][field] = 'wrong'
            with self.subTest(field=field), self.assertRaisesRegex(Mismatch, 'call 0'):
                compare(wanted, changed, 2)
        for field in ('call', 'width', 'height', 'rgba_sha256', 'index'):
            changed = copy.deepcopy(wanted)
            changed['frames'][0][field] = 'wrong'
            with self.subTest(field=field), self.assertRaisesRegex(Mismatch, 'frame 0'):
                compare(wanted, changed, 2)

    def test_real_pixel_rehash_omission_and_order_controls(self):
        """Actual candidate pixel mutation changes its observed SHA; missing/reordered actual receipts also refuse."""
        wanted = observed()
        changed = rgba_frames(events(9), 0, 0)+wanted['frames'][1:]
        rows = negative_frames(wanted, copy.deepcopy(wanted), 2, changed)
        self.assertEqual([r['control'] for r in rows], ['changed-pixel','omitted-frame','reordered-frame'])
        self.assertTrue(all(r['refused'] for r in rows))
        self.assertIn('frame 0', rows[0]['diagnostic'])
        self.assertIn('reordered', rows[2]['diagnostic'])

    def test_truncated_foreign_and_missing_video_cannot_certify_a_frame(self):
        """Only a complete bounded pinned video ABI can generate frame receipts."""
        for data in (b'', events()[:-1], b'\x01\x01\x00\x00\x00x', b'\x09\x00\x00\x00\x00'):
            with self.subTest(prefix=data[:8]), self.assertRaises(ValueError):
                rgba_frames(data, 0, 0)

    def test_interop_native_architectures_and_aggregate_own_the_check(self):
        """Master/full/Interop execute native shared backends; focused dispatch avoids unrelated families."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = job_section(text, 'pvm-doom-backends')
        self.assertIn('Interop / PVM Backends', section)
        self.assertIn('ubuntu-26.04-arm', section)
        self.assertIn('ubuntu-26.04', section)
        self.assertIn('make check-pvm-doom-backends', section)
        self.assertIn('needs: [interop, pvm-doom-backends]', job_section(text, 'interop-status'))
        for context in (event_context('push'), event_context('workflow_dispatch', suite='pvm-backends'),
                        event_context('workflow_dispatch', suite='interop'),
                        event_context('workflow_dispatch', suite='full')):
            with self.subTest(context=context):
                self.assertTrue(expression(job_condition(text, 'pvm-doom-backends'), context))

    def test_focused_aggregate_only_excuses_intentionally_skipped_other_families(self):
        """Focused dispatch cannot hide a failed backend or an unexpectedly failed ordinary Interop job."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        gate = job_section(text, 'interop-status')
        command = re.search(r'        run: ([^\n]+)', gate).group(1)
        for ordinary in ('success', 'skipped', 'failure', 'cancelled'):
            for backends in ('success', 'skipped', 'failure', 'cancelled'):
                env = dict(SHARDS_RESULT=ordinary, BACKENDS_RESULT=backends, FOCUSED='true')
                status = subprocess.run(['bash', '-c', command], env=env).returncode
                self.assertEqual(status == 0, backends == 'success' and ordinary in ('success', 'skipped'))


if __name__ == '__main__':
    unittest.main()
