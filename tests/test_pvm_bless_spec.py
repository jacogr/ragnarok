# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Retain the pinned bless set-versus-dictionary discrepancy without choosing an overwrite rule."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BlessSpecificationGate(unittest.TestCase):
    """Source evidence and an independent set witness keep the unsupported input boundary explicit."""

    def test_conflicting_pairs_are_not_a_dictionary(self):
        """The pinned row constructs a set of pairs, allowing conflicting values for one key."""
        text = (ROOT/'vendor/graypaper/text/pvm_invocations.tex').read_text()
        row = text.split(r'\texttt{bless} = 15', 1)[1].split(r'\texttt{assign} = 16', 1)[0]
        self.assertIn(r'\set{\build{\kv{s}{g}', row)
        pairs = {(1, 1), (1, 2)}
        self.assertEqual(len(pairs), 2)
        self.assertEqual(len({service for service, _ in pairs}), 1)

    @unittest.skip('Conflicting bless allowance pairs await an explicit dictionary interpretation')
    def test_conflicting_allowance_parity(self):
        """A local ambiguity refusal must not claim protocol parity for conflicting gas values."""
        self.fail('Resolve the dictionary interpretation before adopting a protocol overwrite/rejection rule')
