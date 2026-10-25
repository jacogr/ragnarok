# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole-state profile anchors and source-shape checks, separate from native output."""
import hashlib
import json
from pathlib import Path
import unittest
from state_serialization_profiles_oracle import PROFILES, cases, encoded
from state_complete_serialization_oracle import MAGIC

class SerializationProfilesOracleTests(unittest.TestCase):
    """Require all chain cardinalities and alternatives without silently updating expected roots."""
    @classmethod
    def setUpClass(cls):
        """Generate the expensive full-profile inputs once for this focused reference suite."""
        cls.rows = list(cases())
        cls.anchors = json.loads((Path(__file__).parent/'fixtures/serialization-profiles-anchors.json').read_text())

    def test_complete_anchors(self):
        """Exact roots, extents and every chapter digest retain independently reviewed identities."""
        observed = [dict(profile=list(profile), kind=kind, case=case,
                         root=wire[25:57].hex(), bytes=len(wire),
                         chapter_sha256=[hashlib.sha256(value).hexdigest() for value in values])
                    for profile, kind, case, values, wire in self.rows]
        self.assertEqual(observed, self.anchors['cases'])
        self.assertEqual(hashlib.sha256(encoded()).hexdigest(), self.anchors['fixture_sha256'])
        self.assertEqual(len({row['root'] for row in observed}), 8)

    def test_profile_and_widths(self):
        """Fixed queue/entropy/time widths, two schedule forms and resized rosters remain explicit."""
        self.assertEqual({profile for profile, *_ in self.rows}, set(PROFILES))
        for profile, kind, case, values, wire in self.rows:
            cores, current, previous, slots = profile
            self.assertEqual(len(values), 16)
            self.assertEqual(len(values[1]), cores*80*32)
            self.assertEqual(len(values[5]), 128)
            self.assertEqual(values[10], b'\xff'*4)
            self.assertEqual(wire[:len(MAGIC)], MAGIC)
            self.assertEqual(int.from_bytes(wire[17:25], 'little'), 20)
            self.assertEqual(values[15][0], 3)
            # Pending/schedule and bare current/previous roster counts have canonical natural prefixes.
            from test_codec import reference_encode
            self.assertEqual(values[7], reference_encode(current)+bytes((59+i) % 251 for i in range(336*current)))
            self.assertEqual(values[8], reference_encode(previous)+bytes((61+i) % 251 for i in range(336*previous)))
            offset = len(reference_encode(current))+336*current+144
            self.assertEqual(values[3][offset], kind)
            self.assertEqual(len(values[3])-offset-1, slots*(33 if kind == 0 else 32)+1+33)
            self.assertEqual(case % 2, kind)
