# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Strict minifuzz provisioning/framing refuses altered sources, incomplete frames and unsafe archive paths."""
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
from setup_jam_minifuzz import source_files, retain_source, PINS
from jam_minifuzz_replay import receive, send
from jam_minifuzz_trace import write_trace


class FragmentedPeer:
    """Test transport returns bounded partial reads, independently of a real socket's chunking."""

    def __init__(self, data):
        self.data = bytearray(data)
        self.sent = b''

    def recv(self, size):
        result = bytes(self.data[:min(size, 2)])
        del self.data[:len(result)]
        return result

    def sendall(self, data):
        self.sent += data


class MinifuzzBoundaries(unittest.TestCase):
    """Test exact pinned-source ownership, safe extraction and complete bounded frame observations."""

    def archive(self, name='source/value.py'):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive:
            archive.writestr(name, b'value = 1\n')
        return buffer.getvalue()

    def test_source_archive_and_warm_tree(self):
        """A pristine warm source is reusable; modified or injected files cannot silently become upstream code."""
        data = self.archive()
        self.assertEqual(source_files(data, 'source'), {'value.py': b'value = 1\n'})
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder)/'source'
            retain_source(data, target, 'source')
            retain_source(data, target, 'source')
            (target/'value.py').write_bytes(b'value = 2\n')
            with self.assertRaises(ValueError): retain_source(data, target, 'source')
            (target/'value.py').write_bytes(b'value = 1\n')
            (target/'injected.py').write_bytes(b'')
            with self.assertRaises(ValueError): retain_source(data, target, 'source')
        for name in ('/source/a', 'source/../a', 'source/./a', 'source//a', 'other/a'):
            with self.assertRaises(ValueError): source_files(self.archive(name), 'source')

    def test_complete_bounded_frames(self):
        """Fragmentation preserves exact bytes; zero/oversized extents and every truncated suffix fail."""
        payload = b'\x02'+bytes(32)
        frame = struct.pack('<I', len(payload))+payload
        self.assertEqual(receive(FragmentedPeer(frame)), payload)
        for index in range(len(frame)):
            with self.assertRaises(ValueError): receive(FragmentedPeer(frame[:index]))
        for size in (0, 16777217, 2**32-1):
            with self.assertRaises(ValueError): receive(FragmentedPeer(struct.pack('<I', size)))
        peer = FragmentedPeer(b'')
        send(peer, payload)
        self.assertEqual(peer.sent, frame)

    def test_trace_pairs_are_exact_and_fresh(self):
        """A manifest binds every raw binary pair; stale or unrelated directory contents refuse replay."""
        pair = (b'\x04'+bytes(32), b'\x05\x00')
        with tempfile.TemporaryDirectory() as folder:
            files = write_trace(folder, [pair])
            self.assertEqual(len(files), 2)
            self.assertEqual((Path(folder)/'00000000_fuzzer_get_state.bin').read_bytes(), pair[0])
            with self.assertRaises(ValueError): write_trace(folder, [pair])

    def test_pure_dependency_pins(self):
        """No floating upstream ref, source installer or platform-native wheel enters the isolated codec path."""
        pins = json.loads(PINS.read_text())
        for entry in pins['sources'].values():
            self.assertRegex(entry['commit'], r'^[0-9a-f]{40}$')
            self.assertIn(entry['commit'], entry['url'])
            self.assertRegex(entry['sha256'], r'^[0-9a-f]{64}$')
        for entry in pins['wheels'].values():
            self.assertTrue(entry['filename'].endswith('none-any.whl'))
            self.assertRegex(entry['sha256'], r'^[0-9a-f]{64}$')

    def test_original_last_finite_sibling_queries(self):
        """Nine variants leave seven retained variants after original-last occupies the eighth position."""
        from collections import Counter
        from state_layout_oracle import digest
        from jam_minifuzz_trace import exchanges, retained_sibling_queries
        state = bytes(32)+b'\0'
        steps = [dict(kind='V',header=b'variant'+bytes([index]),block=b'block'+bytes([index]),state=state) for index in range(9)]
        steps += [dict(kind='B',header=b'original',block=b'original-block',state=state),
                  dict(kind='B',header=b'child',block=b'child-block',state=state)]
        job = dict(header=b'seed',state=state,initialize=b'initialize',steps=steps,fork_capacity=8)
        self.assertEqual(retained_sibling_queries(job),7)
        queries = Counter(request[1:] for request,_ in exchanges(job) if request[:1] == b'\x04')
        for index,step in enumerate(steps[:9]):
            self.assertEqual(queries[digest(step['header'])],1 if index < 2 else 2)
        # A one-position window retains the original alone, with no accidental negative-zero slice.
        job['fork_capacity'] = 1
        self.assertEqual(retained_sibling_queries(job),0)
        queries = Counter(request[1:] for request,_ in exchanges(job) if request[:1] == b'\x04')
        self.assertTrue(all(queries[digest(step['header'])] == 1 for step in steps[:9]))
        for invalid in (0,65,True):
            job['fork_capacity'] = invalid
            with self.assertRaises(AssertionError): exchanges(job)
        job['fork_capacity'] = 8;job['steps'] = steps[:9]
        with self.assertRaises(AssertionError): exchanges(job)
