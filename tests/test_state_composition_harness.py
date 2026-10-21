# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal extent, domain and complete-map anchors for the independent composition reference.

Exposes StateCompositionHarness for unittest discovery; test methods exercise the stated
contracts.
"""
import unittest
from state_composition_oracle import chapters, capture, entries, composed, PROFILE, POLICY
from state_layout_oracle import chapter_key, chapter_service, MAX
from state_service_values_oracle import key as service_key
from state_trie_oracle import tree


# Small equations keep the harness independently reviewable without a compiler or upstream fetch.
class StateCompositionHarness(unittest.TestCase):
    # Every authored baseline chapter has its full fixed/variable shape, including sixteen mandatory keys.
    def test_baseline(self):
        values = chapters()
        self.assertEqual(len(values), 16)
        self.assertEqual(values[10], b'\4\3\2\1')
        self.assertEqual(len(values[1]), 5120)
        self.assertEqual([capture(i+1, raw) for i, raw in enumerate(values)], ['ok']*16)
        self.assertEqual([key for key, _ in entries(values, [])], [chapter_key(i) for i in range(1, 17)])

    # Prefix APIs are stricter at the state boundary: an additional byte is never silently ignored.
    def test_exact_extent(self):
        self.assertEqual(capture(11, bytes(4)), 'ok')
        self.assertEqual(capture(11, bytes(3)), 'truncated')
        self.assertEqual(capture(11, bytes(5)), 'trailingbytes')
        self.assertEqual(capture(16, b'\x80\0'), 'noncanonical')

    # Invalid shared profiles precede input policy, and externally delimited bytes obey the whole ceiling.
    def test_policy(self):
        self.assertEqual(capture(6, bytes(128), (1, 6, 6, 2), (0, 0)), 'invalidconfig')
        self.assertEqual(capture(6, bytes(128), PROFILE, (0, 127)), 'limitexceeded')
        self.assertEqual(capture(6, bytes(128), PROFILE, (0, 128)), 'ok')
        self.assertEqual(capture(13, chapters()[12], PROFILE, POLICY), 'ok')

    # A service always contributes its fixed metadata; nested present-empty storage still creates a leaf.
    def test_service_mapping(self):
        service = (7, bytes(105), [(b'', b'')], [], [], [])
        pairs = entries(chapters(), [service])
        self.assertEqual(len(pairs), 18)
        self.assertEqual(pairs[16], (chapter_service(255, 7), bytes(105)))
        self.assertEqual(pairs[17], (service_key('S', 7, b''), b''))

    # Both deterministic namespace overlaps reject rather than silently selecting one value.
    def test_namespace_overlap(self):
        h = bytes(32)
        for storage, preimages, length in (([], [(h, b'p')], 2**32-2), ([(h, b's')], [], 2**32-1)):
            self.assertEqual(composed(chapters(), [(7, bytes(105), storage, preimages, [(h, length, ())], [])],
                (MAX,)*4, MAX), 'invalidcomponent')

    # Entry count and complete bytes include every chapter and the metadata of otherwise empty services.
    def test_parent_limits(self):
        values = chapters()
        pairs = entries(values, [])
        root, nodes = tree(pairs)
        limits = (16, max(len(v) for _, v in pairs), sum(len(v) for _, v in pairs), nodes)
        self.assertTrue(composed(values, [], limits, 0).startswith(root.hex()+' 16 '+str(nodes)+' '))
        self.assertEqual(composed(values, [], (15, *limits[1:]), MAX), 'limitexceeded')
        self.assertEqual(composed(values, [(7, bytes(105), [], [], [], [])], limits, MAX), 'limitexceeded')

    # Reusing an opaque entry preserves its exact existing service-key identity and raw bytes.
    def test_opaque_capture(self):
        key = service_key('S', 7, b'original')
        pairs = entries(chapters(), [(7, bytes(105), [], [], [], [(key, b'raw')])])
        self.assertEqual(pairs[-1], (key, b'raw'))
        self.assertEqual(len(pairs), 18)


# Literal tests never build native code or execute an upstream generator.
if __name__ == '__main__':
    unittest.main()
