# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Bind native CE144/145 byte witnesses to independent fixed-width serialization expectations."""
from pathlib import Path
import unittest
from jamnp_audit_oracle import samples


class AuditWireWitnesses(unittest.TestCase):
    """Keep tagged intent, compact credential counts and inline guarantee placement observable."""

    def test_frozen_witnesses(self):
        """Native tests consume the same independently constructed immutable wire files."""
        folder = Path(__file__).parent/'fixtures/jamnp-audit'
        expected = samples()
        self.assertEqual({path.name for path in folder.iterdir()}, set(expected))
        for name, wire in expected.items():
            with self.subTest(name=name):
                self.assertEqual((folder/name).read_bytes(), wire)

    def test_offsets_and_lengths(self):
        """Assert normative field boundaries directly, without round-tripping a production codec."""
        wire = samples()
        self.assertEqual([len(wire[name]) for name in ('initial.bin', 'later.bin', 'positive.bin',
                                                     'negative2.bin', 'negative3.bin')],
                         [131, 133, 103, 240, 306])
        self.assertEqual(wire['later.bin'][32:37], bytes.fromhex('fe03015401'))
        self.assertEqual(wire['negative2.bin'][6:14], bytes.fromhex('00ddccbbaa020200'))
        self.assertEqual(wire['negative2.bin'][144:176], b'\x55'*32)
        self.assertEqual(wire['negative3.bin'][210:242], b'\x77'*32)
        self.assertEqual(wire['positive.bin'][:7], bytes.fromhex('04030201110001'))
