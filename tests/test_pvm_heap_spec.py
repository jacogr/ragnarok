# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Keep the pinned grow_heap gas and stack-rounding discrepancies explicit before host dispatch."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HeapSpecificationGate(unittest.TestCase):
    """Witness unresolved host semantics without adopting vector deviations as normative rules."""

    def test_pinned_gas_discrepancy(self):
        """The GP retains credit on growth OOG while the pinned vectors document draining it."""
        text = (ROOT / 'vendor/graypaper/text/pvm_invocations.tex').read_text()
        changelog = (ROOT / 'vendor/jamtestvectors/CHANGELOG.md').read_text()
        self.assertIn(r'\tup{\oog, \gascounter, h}', text)
        self.assertIn('gas counter is drained to zero', changelog)
        credit, base, per_page, additional = 300, 275, 121, 1
        self.assertLess(credit, base + per_page * additional)
        self.assertNotEqual(credit, 0)  # Retaining credit and draining it cannot share a verdict.

    def test_pinned_stack_rounding_discrepancy(self):
        """A one-byte stack excludes fifteen additional pages under the vector deviation."""
        text = (ROOT / 'vendor/graypaper/text/pvm_invocations.tex').read_text()
        changelog = (ROOT / 'vendor/jamtestvectors/CHANGELOG.md').read_text()
        self.assertIn(r'\Cpvminitinputsize - \rnp{s}', text)
        self.assertIn('64 KiB zone size', changelog)
        address_limit = 2**32 - 3 * 65536 - 2**24
        gp_past = (address_limit - 4096) // 4096
        vector_past = (address_limit - 65536) // 4096
        self.assertEqual(gp_past - vector_past, 15)

    @unittest.skip('grow_heap gas semantics await an explicit decision on GP 0.8.0 versus PR #533')
    def test_grow_heap_gas_parity(self):
        """Pending host-level parity; primitive memory success must not close this gate."""
        self.fail('Resolve gas affordability/terminal credit and add host boundary witnesses')

    @unittest.skip('grow_heap heap ceiling awaits an explicit decision on GP 0.8.0 versus PR #538')
    def test_grow_heap_address_space_parity(self):
        """Pending envelope-derived heap boundary parity for non-zone-sized stacks."""
        self.fail('Resolve stack rounding and add host boundary witnesses')
