# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect the independently frozen complete operand matrix and short-encoding boundary witnesses."""
import hashlib
import json
import unittest
from dependencies import ROOT
from pvm_operand_reference import COUNT,DESCRIPTORS,ROW,fixtures,operands,shape
from pvm_gas_reference import tables


class OperandReferenceTests(unittest.TestCase):
    """Every published opcode/shape/skip/descriptor/address combination must remain represented."""

    def test_frozen_complete_matrix(self):
        """Frozen bytes reproduce independently and cover the exact Cartesian product without duplicates."""
        data,count=fixtures();self.assertEqual(count,62550)
        self.assertEqual(data,(ROOT/'tests/fixtures/pvm-operand.bin').read_bytes())
        descriptor=json.loads((ROOT/'tests/fixtures/pvm_operand.fixture.json').read_text())
        self.assertEqual(hashlib.sha256(data).hexdigest(),descriptor['files']['pvm-operand.bin'])
        cursor=12;seen=set()
        for row in range(COUNT):
            size,pc,op,skip,kind,a,b,d,jam,variant,x,y,disp=ROW.unpack_from(data,cursor)
            self.assertEqual(kind,shape(op));self.assertLessEqual(max(a,b,d,jam),12)
            key=(op,skip,variant,pc);self.assertNotIn(key,seen);seen.add(key)
            self.assertEqual(data[cursor+ROW.size+3+pc],op)
            cursor+=ROW.size+size
        self.assertEqual(cursor,len(data))
        self.assertEqual(seen,{(op,skip,v,pc) for op in tables()[0] for skip in range(25)
                               for v in range(len(DESCRIPTORS)) for pc in (0,3)})

    def test_short_extended_read_sees_following_marked_bytes(self):
        """A fixed eight-byte immediate crosses marked instructions and then reads semantic zero padding."""
        values=operands(bytes((20,51,8,128,0)),0,0)
        self.assertEqual(values,(2,3,0,0,0,0x8008,0,0))
        values=operands(bytes((30,51,8,128,0)),0,0)
        self.assertEqual(values,(3,0,0,0,0,0x8008,0,0))

    def test_signed_offsets_and_destination_profile(self):
        """Negative offsets retain mathematical signs; both profiles follow the current low-nibble destination equation."""
        self.assertEqual(operands(bytes((40,255,0)),0,1)[-1],-1)
        self.assertEqual(operands(bytes((190,0xff,0x10,0)),0,2)[:5],(12,12,12,0,0))
        self.assertEqual(operands(bytes((51,0xff,128,0)),0,2)[5],(1<<64)-128)
