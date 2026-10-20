# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Keep frozen native bundle witnesses reproducible from the independent literal Python reference."""
import re
import unittest
from pathlib import Path
from pvm_bundle_reference import witnesses


def frozen_bytes(source, name):
    """Read only named generated array literals, never production codec output or runtime state."""
    match = re.search(r'const\s+' + name + r'\*\s*=\s*\[([^]]*)\]', source, re.S)
    assert match is not None, name
    return bytes(int(part.strip().replace("'u8", '')) for part in match[1].split(',') if part.strip())


class BundleReferenceTests(unittest.TestCase):
    """Check fixture provenance and the canonical boundary facts independently of native execution."""

    def test_frozen_package_and_hash_bytes(self):
        """Both complete bundle witnesses regenerate their package prefix and final hash exactly."""
        source = (Path(__file__).parent/'support/pvm_bundle_vectors.nim').read_text()
        # Ordinary and mixed empty/repeated layouts must each match their frozen independent arrays.
        for kind in ('ordinary', 'rich'):
            expected = witnesses()[kind]
            self.assertEqual(frozen_bytes(source, kind.capitalize()+'Package').hex(), expected['package'])
            self.assertEqual(frozen_bytes(source, kind.capitalize()+'Hash').hex(), expected['hash'])

    def test_blob_commitments(self):
        """The two natural-width boundary blobs have independently frozen raw-byte commitments."""
        source = (Path(__file__).parent/'support/pvm_bundle_vectors.nim').read_text()
        values = witnesses()
        self.assertEqual(frozen_bytes(source, 'Long128Hash').hex(), values['long128_hash'])
        self.assertEqual(frozen_bytes(source, 'Long129Hash').hex(), values['long129_hash'])

    def test_section_lengths(self):
        """No-prefix section extents remain explicit rather than inferred from observed native success."""
        values = witnesses()
        fields = ('length', 'extrinsic_bytes', 'segment_bytes', 'proof_bytes')
        self.assertEqual([values['ordinary'][key] for key in fields], [8813, 6, 8208, 130])
        self.assertEqual([values['rich'][key] for key in fields], [17637, 385, 16416, 132])


# Standalone focused execution shares unittest discovery's verdict without invoking native builds.
if __name__ == '__main__':
    unittest.main()
