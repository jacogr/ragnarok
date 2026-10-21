# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Keep optional PolkaVM fixture regeneration on upstream-locked dependency identities."""

import hashlib
import struct
import json
import tomllib
import unittest
from dependencies import ROOT, require_submodule


class MemoryReferenceTests(unittest.TestCase):
    """A test-only reference crate must not introduce an implicit upstream dependency upgrade."""

    def test_boundary_fixture_and_original_prefix(self):
        """Retain the original byte witnesses and complete absent/RW/RO coverage for every scalar form."""
        data = (ROOT/'tests/fixtures/pvm-memory-boundary.bin').read_bytes()
        self.assertEqual(data[:8],b'PVMMEM01')
        self.assertEqual(len(data),2262)
        self.assertEqual(struct.unpack_from('<I',data,8)[0],90)
        original = data[:8]+struct.pack('<I',12)+data[12:312]
        self.assertEqual(hashlib.sha256(original).hexdigest(),
                         '9a27ed2322e3615c6cacceb63f1d10610c88866d25ac121f03e43e0efe684089')
        manifest = json.loads((ROOT/'tests/fixtures/pvm_memory_boundary.fixture.json').read_text())
        self.assertEqual(hashlib.sha256(data).hexdigest(),manifest['files']['pvm-memory-boundary.bin'])
        rows = {(data[12+25*i+9],struct.unpack_from('<Q',data,12+25*i)[0],data[12+25*i+8]) for i in range(90)}
        self.assertEqual(len(rows),90)
        for opcode,width in zip(range(52,63),(1,1,2,2,4,4,8,1,2,4,8)):
            addresses = {0xffffffff-width,0x100000000-width,0xffffffff}
            for address in addresses:
                for mapping in range(3):self.assertIn((opcode,address,mapping),rows)

    def test_generator_lock_matches_upstream(self):
        """Compare every resolved package's identity and checksum, excluding our independent root."""
        entry = json.loads((ROOT/'spec/polkavm-pins.json').read_text())
        upstream = require_submodule(entry)
        original = tomllib.loads((upstream/'Cargo.lock').read_text())['package']
        reference = tomllib.loads((ROOT/'tests/reference/polkavm_memory/Cargo.lock').read_text())['package']
        fields = ('name', 'version', 'source', 'checksum')
        known = {tuple(package.get(field) for field in fields) for package in original}
        compared = 0
        for package in reference:
            # Our generator is the sole new package; all transitive packages retain upstream identity.
            if package['name'] != 'ragnarok-memory-probe':
                self.assertIn(tuple(package.get(field) for field in fields), known, package['name'])
                compared += 1
        self.assertGreater(compared, 0)


if __name__ == '__main__':
    # Direct execution checks metadata only and never builds a Rust runtime.
    unittest.main(verbosity=2)
