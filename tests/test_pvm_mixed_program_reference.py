# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Freeze complete mixed-program outcomes and independent wrapped arithmetic/gas expectations."""
import hashlib
import json
import unittest
from pvm_mixed_program_reference import ROOT, HEADER, MASK, fixtures


class MixedProgramReferenceTests(unittest.TestCase):
    """Full-program fixture expectations must remain independent of either execution engine."""

    def test_frozen_corpus_and_gas(self):
        """All loop counts, value carries, address placements and both block prices remain covered."""
        data,count=fixtures()
        self.assertEqual(count,32)
        self.assertEqual(data,(ROOT/'tests/fixtures/pvm-mixed-program.bin').read_bytes())
        descriptor=json.loads((ROOT/'tests/fixtures/pvm_mixed_program.fixture.json').read_text())
        self.assertEqual(hashlib.sha256(data).hexdigest(),descriptor['files']['pvm-mixed-program.bin'])
        cursor=12;seen=set()
        while cursor<len(data):
            # Fixed records expose literal expectations without importing a guest or host implementation.
            row=HEADER.unpack_from(data,cursor)
            self.assertEqual(row[5:9],(103,106,22,25))
            seen.add((row[1],row[3],row[2]))
            cursor+=HEADER.size+row[0]
        self.assertEqual(cursor,len(data))
        self.assertEqual(seen,{(n,value,address) for n in (1,2,7,31)
            for value in (0,MASK,(1<<63)-1,1<<63) for address in (0x10000,0x10fff)})

    def test_literal_carry_and_accumulation(self):
        """Known carries and triangular sums catch mistakes in the complete-program oracle."""
        data,_=fixtures();cursor=12;observed={}
        while cursor<len(data):
            # Posterior r7/r8/r10 follow from host increment/sum and the guest loop counter.
            row=HEADER.unpack_from(data,cursor)
            observed[(row[1],row[3])]=(row[22+7],row[22+8],row[22+10])
            cursor+=HEADER.size+row[0]
        self.assertEqual(observed[(1,MASK)],(0,0,1))
        self.assertEqual(observed[(2,MASK)],(1,1,2))
        self.assertEqual(observed[(2,1<<63)],((1<<63)+2,3,2))
        self.assertEqual(observed[(31,0)],(31,496,31))


# Direct execution checks independent expected bytes only; native execution belongs to Make.
if __name__=='__main__':
    unittest.main(verbosity=2)
