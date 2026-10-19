# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Keep participating-target validity unresolved while checking pinned removal/credit evidence."""

import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DeletionSpecificationGate(unittest.TestCase):
    """Separate the account-set formula from the following collision validity requirement."""

    def test_pinned_removal_and_collision_clauses(self):
        """Both reviewed files match their pins and retain the clauses behind the gate."""
        pins = json.loads((ROOT / 'spec/pins.json').read_text())['graypaper']
        for name in ['accumulation', 'pvm_invocations']:
            # Refuse silently changed authority before evaluating any quoted evidence.
            relative = f'text/{name}.tex'
            source = ROOT / 'vendor/graypaper' / relative
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),
                             pins['source_sha256'][relative])
        text = (ROOT / 'vendor/graypaper/text/accumulation.tex').read_text()
        self.assertIn(r'(\ps¬accounts \cup \mathbf{n}) \setminus \mathbf{m}', text)
        self.assertIn('different services may not each contribute the same index', text)
        self.assertIn('the block must be considered invalid', text)
        invocation = (ROOT / 'vendor/graypaper/text/pvm_invocations.tex').read_text()
        row = invocation.split(r'\label{eq:accinvocation}', 1)[1].split(
            r'  I&\colon', 1)[0]
        self.assertIn(r'\is{\ao¬poststate}{\local¬postxferstate}', row)
        self.assertIn(r'\when \jam¬blob = \none', row)
        self.assertIn(r'\sa¬balance + \sum_{r \in \mathbf{x}}r_\dx¬amount', row)

    def test_credited_skip_overlaps_removal(self):
        """Literal balances expose the discarded credit without choosing block validity."""
        prior = {42: 10, 99: 20}
        ejector = {42: 37}
        skipped = {42: 10, 99: 31}
        removed = set(prior) - set(ejector)
        contributed = {42: ejector[42], 99: skipped[99]}
        self.assertEqual(removed & set(contributed), {99})
        # The formula alone removes the target after union, including its eleven-unit credit.
        formula = {service: balance for service, balance in (prior | contributed).items()
                   if service not in removed}
        self.assertEqual(formula, {42: 37})
        self.assertEqual(sum(prior.values()) + 7 + 11 - sum(formula.values()), 11)

    def test_recreation_is_not_final_domain_removal(self):
        """A prior ID recreated before terminal selection cannot enter m from that outcome."""
        prior = {42, 99}
        selected_after_recreation = {42, 99}
        self.assertEqual(prior - selected_after_recreation, set())

    @unittest.skip('GP 0.8.0 participating skip needs collision-validity interpretation')
    def test_participating_skip_protocol_parity(self):
        """Resolve credited and unchanged self contributions before changing the local gate."""
        self.fail('Decide validity from the collision paragraph before claiming deletion precedence')
