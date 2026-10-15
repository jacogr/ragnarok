#!/usr/bin/env python3
"""Independent contract examples for the frozen assurances oracle and source profile correction."""
import unittest
from assurances_oracle import decode, encode, logical, official, record, requests, wire
from report_oracle import requests as report_requests


# Concrete protocol examples catch oracle mistakes before native agreement can conceal them.
class AssurancesOracleTests(unittest.TestCase):
    # Two cores use one LSB-first octet; anchor, E2 index and signature occupy fixed offsets.
    def test_tiny_layout(self):
        value = (bytes(32), bytes([2])+bytes(42), 5, bytes([0xA5])*64)
        expected = b'\x01'+bytes(32)+b'\x02\x05\x00'+bytes([0xA5])*64
        self.assertEqual(wire([value], 2), expected)
        self.assertEqual(len(expected), 100)
        self.assertEqual(decode(2, 6, 1, expected), '1 '+logical([value]).hex()+' 100')

    # Full core 340 is bit four of the final byte, and validator 1022 is fe03 in E2.
    def test_full_boundaries(self):
        value = (bytes(32), bytes(42)+b'\x10', 1022, bytes(64))
        data = wire([value], 341)
        self.assertEqual(data[75:78], b'\x10\xfe\x03')
        self.assertEqual(len(data), 142)
        self.assertTrue(decode(341, 1023, 1, data).startswith('1 '))

    # Invalid profile, count, wire extent and typed capacity retain explicit failure precedence.
    def test_precedence(self):
        self.assertEqual(decode(0, 0, 0, b''), 'invalidconfig')
        self.assertEqual(decode(2, 6, 0, b'\x07'), 'limitexceeded')
        self.assertEqual(decode(2, 6, 0, b'\x01'), 'truncated')
        self.assertEqual(decode(2, 6, 0, wire([record(6, 2)], 2)), 'outputtoosmall')
        self.assertEqual(encode(2, 6, 0, [record(6, 2)]), 'outputtoosmall')
        self.assertEqual(decode(2, 6, 1, wire([record(6, 2)], 2)), 'invalidvalidator')

    # Omitted native storage is an encoder constraint; nonexistent wire padding cannot be decoded.
    def test_padding_and_order(self):
        value = list(record(0, 2)); value[1] = b'\x04'+bytes(42)
        self.assertEqual(decode(2, 6, 1, wire([value], 2)), 'noncanonical')
        value[1] = bytes(42)+b'\x01'
        self.assertEqual(encode(2, 6, 150000, [value]), 'noncanonical')
        self.assertTrue(decode(2, 6, 1, wire([value], 2)).startswith('1 '))
        self.assertEqual(decode(2, 6, 2, wire([record(1, 2), record(0, 2)], 2)), 'noncanonical')

    # Hash-pinned official JSON fields independently reproduce their unmodified binary fixtures.
    def test_official_and_corpus(self):
        self.assertEqual(len(official('tiny', 2)), 2)
        self.assertEqual(len(official('full', 341)), 2)
        lines, expected = requests()
        self.assertEqual(len(lines), 20706)
        self.assertEqual(len(lines), len(expected))
        self.assertIn('XE 2 6 ', '\n'.join(lines))
        self.assertEqual(len(report_requests()[0]), 18430)


# These tests validate shared infrastructure; they are excluded from native defect metrics.
if __name__ == '__main__':
    unittest.main()
