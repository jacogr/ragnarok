# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal known answers and independent policy checks protect the package oracle itself.

Exposes PackageHarness for unittest discovery; test methods exercise the stated contracts.
"""
import copy
import unittest
from package_oracle import DEFAULT,MAX_BUNDLE,example,published,wire,fields,decode,encode


# Known offsets/limits distinguish independent oracle correctness from native same-codec round trips.
class PackageHarness(unittest.TestCase):
    # Seven context fields occupy 168 bytes; their count follows both fixed E4 timeslots.
    def test_context(self):
        value=example('C');data=wire('C',value)
        self.assertEqual(len(data),169)
        self.assertEqual(data[32:36],bytes.fromhex('ffffffff'))
        self.assertEqual(data[132:136],bytes.fromhex('80000000'))
        self.assertEqual(data[168:],b'\0')
        self.assertEqual(decode('C',data+b'x',DEFAULT),'169 '+fields('C',value))

    # Selector bit and fifteen-bit index boundaries have literal two-octet known answers.
    def test_selector(self):
        value=example('R');data=wire('R',value)
        self.assertEqual(data[32:],bytes.fromhex('ff7f'))
        value.update(kind=1,index=0)
        self.assertEqual(wire('R',value)[32:],bytes.fromhex('0080'))
        self.assertEqual(decode('R',wire('R',value),DEFAULT),'34 '+fields('R',value))
        value['index']=32768
        self.assertEqual(encode('R',value,DEFAULT,100),'limitexceeded')

    # E4 advertised length, E8 gas and E2 exports differ from compact counts at independently named offsets.
    def test_fixed_item_fields(self):
        value=example('I');data=wire('I',value)
        self.assertEqual(data[:4],b'\xff'*4)
        self.assertEqual(data[36:44],b'\1'+bytes(7))
        self.assertEqual(data[44:52],b'\1'+bytes(7))
        self.assertEqual(data[52:55],bytes.fromhex('020003'))
        commitment=example('X');commitment['len']=0x12345678
        self.assertEqual(wire('X',commitment)[32:],bytes.fromhex('78563412'))

    # Every exact pinned standalone/package source reconstructs its published binary without source edits.
    def test_published(self):
        for profile in ('tiny','full'):
            # JSON-to-binary agreement runs for all three consumed vector families.
            for kind in ('C','I','P'):
                value=published(kind,profile);data=wire(kind,value)
                self.assertEqual(decode(kind,data,DEFAULT),f'{len(data)} '+fields(kind,value))

    # Packed references and input commitments are sequences; duplicate/order changes are preserved rather than sorted.
    def test_sequences_and_dependencies(self):
        value=example('P');value['items'][0]['import_segments']=[dict(kind=1,hash=bytes(32),index=3)]*20
        data=wire('P',value)
        self.assertEqual(decode('P',data,DEFAULT),f'{len(data)} '+fields('P',value))
        value['context']['prerequisites']=[bytes([i])*32 for i in range(8)]
        self.assertEqual(decode('P',wire('P',value),DEFAULT),'limitexceeded')

    # Equality with a gas ceiling rejects; equality with footprint maximum succeeds.
    def test_strict_and_inclusive_limits(self):
        value=example('I');value['refine_gas_limit']=DEFAULT[0]
        self.assertEqual(encode('I',value,DEFAULT,1000),'limitexceeded')
        value=example('I');value['import_segments']=[];value['payload']=b'';value['extrinsic'][0]['len']=MAX_BUNDLE
        data=wire('I',value)
        self.assertEqual(decode('I',data,DEFAULT),f'{len(data)} '+fields('I',value))
        value['extrinsic'][0]['len']+=1
        self.assertEqual(decode('I',wire('I',value),DEFAULT),'limitexceeded')

    # Two individually admissible gas budgets can fail once aggregated within one package.
    def test_package_totals(self):
        value=example('P');value['items']=[example('I'),example('I')]
        value['items'][0]['refine_gas_limit']=DEFAULT[0]-2;value['items'][1]['refine_gas_limit']=2
        self.assertNotEqual(decode('I',wire('I',value['items'][0]),DEFAULT),'limitexceeded')
        self.assertEqual(decode('P',wire('P',value),DEFAULT),'limitexceeded')
        value['items']=[]
        self.assertEqual(decode('P',wire('P',value),DEFAULT),'limitexceeded')

    # Canonical count and typed configuration failures remain distinguishable without partial progress.
    def test_rejections(self):
        self.assertEqual(decode('C',bytes(168)+b'\x80\0',DEFAULT),'noncanonical')
        self.assertEqual(decode('C',bytes(168)+b'\x09',DEFAULT),'limitexceeded')
        self.assertEqual(decode('P',b'',(0,1,1000)),'invalidconfig')
        self.assertEqual(decode('I',b'',DEFAULT),'truncated')


# Oracle harness checks do not compile native code or mutate upstream source state.
if __name__=='__main__':
    unittest.main(verbosity=2)
