"""Known-answer checks protect independent complete composite framing and nested-error attribution."""
import unittest
from block_oracle import TINY,FULL,example,published,parse,decode,encode,preimage_inspect


# Literal whole-frame rules distinguish reference correctness from a same-codec round trip.
class BlockHarness(unittest.TestCase):
    # Five empty extrinsic families occupy seven natural count bytes, without an outer discriminator.
    def test_empty(self):
        self.assertEqual(b''.join(example('E')),bytes(7))
        self.assertEqual(decode('E',bytes(8),TINY),'7 0 0 0 0 0 00 00 00 00 000000')

    # A complete block is one sealed header followed directly by the five-family extrinsic tuple.
    def test_block_prefix(self):
        parts=example('B');data=b''.join(parts)
        parsed=parse('B',data+b'extra',TINY)
        self.assertEqual(parsed[0],len(data));self.assertEqual(parsed[2],parts)
        self.assertEqual(parsed[1],[1,0,0,0,0,0])

    # Unmodified published bytes reconstruct exactly and retain the already documented structural-policy failures.
    def test_original_vectors(self):
        # Preserve the first policy failure in wire order for each configured profile.
        for profile,config,error in (('tiny',TINY,'guarantees:limitexceeded'),('full',FULL,'disputes:noncanonical')):
            # The same child policy must apply with and without an enclosing header.
            for kind in ('E','B'):
                self.assertEqual(decode(kind,b''.join(published(profile,kind)),config),error)

    # Authored counterparts fix only tiny core bounds and canonical verdict order, without editing upstream samples.
    def test_derived_vectors(self):
        # Both chain profiles exercise independently authored structurally valid counterparts.
        for profile,config in (('tiny',TINY),('full',FULL)):
            # The same child policy must apply with and without an enclosing header.
            for kind in ('E','B'):
                parts=published(profile,kind,canonical=True);data=b''.join(parts)
                self.assertEqual(parse(kind,data,config)[2],parts)
                self.assertEqual(encode(kind,parts,config,config,len(data)),data.hex())

    # A missing final dispute section is attributed to that family; earlier children never constitute parent success.
    def test_late_failure(self):
        self.assertEqual(decode('E',bytes(6),TINY),'disputes:truncated')
        self.assertEqual(decode('E',bytes(4)+b'\x80\0',TINY),'disputes:noncanonical')

    # Preimage payload limits and framing overhead consume separate policies, including empty payload tuples.
    def test_preimage_budget(self):
        data=b'\1'+bytes(4)+b'\0'
        self.assertEqual(preimage_inspect(data,TINY),(6,1))
        self.assertEqual(preimage_inspect(data,TINY[:-1]+(5,)),'limitexceeded')
        self.assertEqual(preimage_inspect(data,TINY[:4]+(0,)+TINY[5:]),'limitexceeded')

    # Reusing previously captured owners under stricter limits cannot bypass whole-parent resource policy.
    def test_stricter_source_policy(self):
        parts=published('tiny','E',canonical=True);strict=list(TINY);strict[3]=0
        self.assertEqual(encode('E',parts,TINY,tuple(strict),0),'tickets:limitexceeded')
        self.assertEqual(encode('E',example('E'),TINY,TINY,6),'outputtoosmall')


# Oracle checks never compile native code or advance pinned dependencies.
if __name__=='__main__':
    unittest.main(verbosity=2)
