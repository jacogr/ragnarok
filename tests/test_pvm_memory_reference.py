# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Keep optional PolkaVM fixture regeneration on upstream-locked dependency identities."""

import json
import tomllib
import unittest
from dependencies import ROOT, require_submodule


class MemoryReferenceTests(unittest.TestCase):
    """A test-only reference crate must not introduce an implicit upstream dependency upgrade."""

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
