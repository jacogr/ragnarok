"""Freeze original independent early-codec request/expectation coverage before native agreement."""
import hashlib
import unittest
from test_codec import natural_requests, fixed_requests, reference_encode, reference_decode
from bounded_checks import batch_requests as bounded_requests
from composite_checks import batch_requests as composite_requests
from digest_checks import batch_requests as digest_requests

# These identities were verified against committed generators before their extraction in the Nimony trial.
IDENTITIES = {'natural': (45215, 'e8dbedcac103a22856270d9ba58ad95aeb83bca5b0b118e5d17d95aa8191d435', '1010554e9dd00f431973af7da947a53626073c79b60d212d46dce9dee7815c62'), 'fixed': (73278, '28382ce153d44c14ac044d78e0557ccc8bfa7aaaccc3cad19f7e21cc7a6f76ad', '56c1b905712b7f86eead5f9ba769c715fe2228f7cd6f2e65e147aef94fa322bc'), 'bounded': (26712, '61bd892bc3546539ece58d4c683b4cfb69efaa249f0ffe778c1ef77db9b5ad49', '224f8d80fea1de6460b93060fd39b8f064346873786c519e369f476c13f6688f'), 'composite': (25890, 'a5f57c02f6e115790135c175506ce5b6a70a2618030b1b869a270bc16a4fc949', 'a910f39644edf0a85834b175320293e6a7dccced68fa89d29a48cf4ae5e77710'), 'digest': (14278, 'b3810a3fcc8c9c45cfbc0162a89eb816266241a3d2a86c12564cc3ca06d90ebb', '01796e849a91e852065017772e4ac2a66b88d2d4e30f395b052254c6ebb6079f')}


# Exact corpus identities prevent a dropped malformed case or changed expectation from hiding a regression.
class EarlyCodecHarness(unittest.TestCase):
    # Preserve complete requests and expected observations, including significant empty payload spaces/lines.
    def check_corpus(self, family, observations):
        lines, expected, *_ = observations
        count, requests_hash, expected_hash = IDENTITIES[family]
        self.assertEqual(len(lines), count)
        self.assertEqual(len(expected), count)
        self.assertEqual(hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest(), requests_hash)
        self.assertEqual(hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest(), expected_hash)

    # Natural encodings include every header/truncation and deliberate textual uint64 overflow.
    def test_natural(self):
        self.check_corpus('natural', natural_requests())

    # All nine supported widths, host extremes and unsupported-width precedence remain independent.
    def test_fixed(self):
        self.check_corpus('fixed', fixed_requests())

    # Byte/element policies, capacities and zero-width hostile counts retain the original oracle.
    def test_bounded(self):
        self.check_corpus('bounded', bounded_requests(reference_encode, reference_decode))

    # Optional/work alternatives and nested preimages retain every policy, tag and truncation case.
    def test_composite(self):
        self.check_corpus('composite', composite_requests(reference_encode, reference_decode))

    # Complete digests preserve every fixed field, metric, output variant and malformed suffix.
    def test_digest(self):
        self.check_corpus('digest', digest_requests(reference_encode, reference_decode))


# These tests generate local reference data only; they never invoke a compiler or upstream generator.
if __name__ == '__main__':
    unittest.main()
