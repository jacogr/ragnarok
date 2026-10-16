"""Literal chapter-13 framing anchors, independent of the production codec."""
import unittest
from state_statistics_oracle import wire,decode,encode,example,DEFAULT,MAX


# Exact byte literals verify each schema family before native corpus execution.
class StatisticsHarness(unittest.TestCase):
    # Two canonical validator counts, fixed E4 tuples and uncounted zero cores precede an empty dictionary.
    def test_zero(self):
        source=([(0,)*6]*6,[(0,)*6]*6,[(0,)*8]*2,[])
        self.assertEqual(wire(source),b'\6'+bytes(144)+b'\6'+bytes(144)+bytes(17))
        self.assertTrue(decode(wire(source)+b'extra',DEFAULT).startswith('307 6:'))

    # A validator counter above 127 still occupies exactly four little-endian bytes.
    def test_fixed_validator(self):
        source=example();source[0][0]=(128,0x01020304,0,0,0,2**32-1)
        self.assertEqual(wire(source)[1:25],b'\x80\0\0\0\4\3\2\1'+bytes(12)+b'\xff'*4)

    # Core and service statistics retain ordinary natural fields, including both service gas positions.
    def test_natural_tuples(self):
        source=([(0,)*6]*6,[(0,)*6]*6,[(0,)*8]*2,[(127,*range(1,12))])
        self.assertEqual(wire(source)[290:],bytes(16)+b'\1\x7f'+bytes(3)+bytes(range(1,12)))
        source[2][0]=(128,0,0,0,0,0,0,MAX)
        self.assertEqual(wire(source)[290:307],b'\x80\x80'+bytes(6)+b'\xff'*9)

    # Dictionary ordering is numeric; E4 service keys retain the full uint32 domain.
    def test_keys(self):
        source=example();source[3][:]=[(256,*(0,)*11),(255,*(0,)*11)]
        self.assertEqual(encode(source,DEFAULT),'noncanonical')
        prefix=b'\6'+bytes(144)+b'\6'+bytes(144)+bytes(16)
        source=([(0,)*6]*6,[(0,)*6]*6,[(0,)*8]*2,[(2**32-1,*(0,)*11)])
        self.assertEqual(wire(source)[307:311],b'\xff'*4)
        self.assertTrue(decode(wire(source),DEFAULT).startswith('322 '))

    # Separate configured populations are required; malformed profiles cannot authorize reads.
    def test_populations(self):
        source=example(6,9,3,0);source[2][:]=[(0,)*8]*3;config=(3,6,9,0,MAX)
        self.assertTrue(decode(wire(source),config).startswith('387 6:'))
        self.assertEqual(decode(wire(source),DEFAULT),'invalidcount')
        self.assertEqual(decode(b'',(2,6,9,0,MAX)),'invalidconfig')

    # Count/byte ceilings and late missing gas reject without a fabricated earlier-state result.
    def test_limits_and_truncation(self):
        data=wire(example())
        self.assertEqual(decode(data,(2,6,6,1,MAX)),'limitexceeded')
        self.assertEqual(decode(data,(2,6,6,2,len(data)-1)),'limitexceeded')
        self.assertEqual(decode(data[:-1],DEFAULT),'truncated')
        self.assertEqual(decode(b'\x80\0',DEFAULT),'noncanonical')

    # Published-style E4 keys now consume their complete fields; incomplete key padding remains truncated.
    def test_e4_trace_extent(self):
        prefix=b'\6'+bytes(144)+b'\6'+bytes(144)+bytes(16)
        original=prefix+b'\1'+bytes(4)+bytes(11)
        self.assertEqual(len(original),322)
        self.assertTrue(decode(original,DEFAULT).startswith('322 6:'))
        self.assertEqual(decode(prefix+b'\1'+bytes(3),DEFAULT),'truncated')
        self.assertEqual(decode(original,(2,6,6,MAX,321)),'limitexceeded')


# Importing harness code never invokes native builds or upstream generators.
if __name__=='__main__':
    unittest.main()
