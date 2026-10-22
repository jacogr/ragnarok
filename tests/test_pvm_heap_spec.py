# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Preserve historical source differences and the maintainer's scoped adoption of merged heap fixes."""

import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


# Independent test-only evaluation of the adopted host row, without production code or memory owners.
def grow(available, requested, current, ceiling):
    returned = requested if current < requested <= ceiling else current
    cost = 275 + 121 * (returned - current)
    if available < cost:
        # The merged general preamble refuses all row-specific mutations and drains gas without debt.
        return 'oog', 0, requested, current
    return 'continue', available - cost, returned, returned


class HeapSpecificationAdoption(unittest.TestCase):
    """Keep precise upstream dispositions separate from unchanged base repository pins."""

    def test_pinned_source_identity(self):
        """The original GP and vector changelog are still exactly the reviewed inputs."""
        pins = json.loads((ROOT / 'spec/pins.json').read_text())
        source = ROOT / 'vendor/graypaper/text/pvm_invocations.tex'
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),
                         pins['graypaper']['source_sha256']['text/pvm_invocations.tex'])
        source = ROOT / 'vendor/jamtestvectors/CHANGELOG.md'
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),
                         pins['vectors']['files']['vendor/jamtestvectors/CHANGELOG.md'])

    def test_recorded_merge_adoption(self):
        """Exact merged revisions record narrow grow_heap adoption, with unchanged vector pins."""
        record = json.loads((ROOT / 'spec/pvm-grow-heap-adoption.json').read_text())
        self.assertEqual([(fix['pr'], fix['commit']) for fix in record['fixes']], [
            (533, '0c0664eb52ba92afd8d21cef96c0e1da506eddfe'),
            (538, 'b76e637c0901f1beb6fc7a63f4e64f8707b94baf')])
        self.assertEqual(record['vectors_commit'],
                         json.loads((ROOT / 'spec/pins.json').read_text())['vectors']['commit'])
        self.assertIn('grow_heap only', record['scope'])

    def test_pinned_gas_discrepancy(self):
        """Original source retains credit; vectors already adopt the merged gas-draining rule."""
        text = (ROOT / 'vendor/graypaper/text/pvm_invocations.tex').read_text()
        changelog = (ROOT / 'vendor/jamtestvectors/CHANGELOG.md').read_text()
        self.assertIn(r'\max(\gascounter - g, 0)', text)
        self.assertIn('gas counter is drained to zero', changelog)
        self.assertEqual(grow(300, 51, 50, 100), ('oog', 0, 51, 50))

    def test_pinned_stack_rounding_discrepancy(self):
        """A one-byte stack reserves fifteen more pages under the adopted zone ceiling."""
        text = (ROOT / 'vendor/graypaper/text/pvm_invocations.tex').read_text()
        changelog = (ROOT / 'vendor/jamtestvectors/CHANGELOG.md').read_text()
        self.assertIn(r'\Cpvminitinputsize - \rnq{s}', text)
        self.assertIn('64 KiB zone size', changelog)
        address_limit = 2**32 - 3 * 65536 - 2**24
        self.assertEqual((address_limit - 4096) // 4096 -
                         (address_limit - 65536) // 4096, 15)

    def test_grow_heap_gas_parity(self):
        """Literal exact/short prices distinguish growth, query, oversized request and OOG mutations."""
        for requested, cost, returned in [(0, 275, 50), (50, 275, 50), (51, 396, 51),
                                          (52, 517, 52), (2**64 - 1, 275, 50)]:
            # OOG retains the original request, and success returns the selected endpoint.
            self.assertEqual(grow(cost - 1, requested, 50, 100),
                             ('oog', 0, requested, 50))
            self.assertEqual(grow(cost, requested, 50, 100),
                             ('continue', 0, returned, returned))

    def test_grow_heap_address_space_parity(self):
        """An endpoint just above the adopted ceiling becomes a base-cost query before arithmetic."""
        base = 2**32 - 3 * 65536 - 2**24
        for stack in [0, 1, 4096, 65535, 65536, 65537]:
            # Round the reservation to whole 64 KiB zones, independently of accessible 4 KiB pages.
            ceiling = (base - ((stack + 65535) // 65536) * 65536) // 4096
            self.assertEqual(grow(275, ceiling + 1, 50, ceiling), ('continue', 0, 50, 50))
            price = 275 + 121 * (ceiling - 50)
            self.assertEqual(grow(price, ceiling, 50, ceiling),
                             ('continue', 0, ceiling, ceiling))
