# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Known upstream sessions retain original versions, bytes and explicitly frozen structural outcomes."""
import unittest
import jam_fuzzer_wire_oracle as reference


class JamFuzzerWireOracle(unittest.TestCase):
    """Published wire evidence cannot silently become a claimed current-profile STF campaign."""

    def test_exact_known_upstream_messages(self):
        """All seven kinds have published witnesses; independent expectations precede native execution."""
        requests,expected,evidence=reference.expected_observations()
        self.assertEqual((len(requests),len(expected),evidence['cases']),(1276,1276,1276))
        self.assertEqual(evidence['accepted']+evidence['refused'],evidence['cases'])
        self.assertEqual(evidence['refusals'],dict(HeaderFailure=7,BlockFailure=310))
        self.assertEqual(set(evidence['variants']),set(reference.NAMES.values()))
        self.assertEqual(evidence['profiles'], {
            '0.7.0': dict(cases=470,accepted=310,refused=160),
            '0.7.2': dict(cases=408,accepted=271,refused=137),
            '0.8.0': dict(cases=398,accepted=378,refused=20)})
        self.assertEqual({name.split('/')[2] for name in evidence['sources']},
                         set(evidence['profiles']))
        self.assertEqual(len(evidence['sources']),2552)
