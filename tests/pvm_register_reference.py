# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent arbitrary-precision GP register oracle and pinned PolkaVM witness extraction."""
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
MASK = (1 << 64) - 1
OPS = (20, 51, *range(100, 111), *range(131, 162), *range(190, 231))
# Direct binary-operation cases only; instruction encodings, hazards and execution are not imported.
UPSTREAM = {'add': 200, 'sub': 201, 'sll': 207, 'srl': 208, 'sra': 209,
            'mul': 202, 'div': 204, 'divu': 203, 'rem': 206, 'remu': 205,
            'mulh': 213, 'mulhu': 214, 'mulhsu': 215,
            'addw': 190, 'subw': 191, 'mulw': 192, 'divw': 194,
            'divuw': 193, 'remw': 196, 'remuw': 195}


# Interpret a low-width unsigned pattern as a mathematical signed integer.
def signed(x, width=64):
    x %= 1 << width
    return x - (1 << width) if x >= (1 << (width - 1)) else x


# Rotate by indexing a fixed-width binary string, independently of the production shift/or method.
def rotate(x, count, width):
    bits = f'{x % (1 << width):0{width}b}'
    n = count % width
    return int(bits[width-n:] + bits[:width-n], 2)


# GP divide truncates toward zero, while its remainder has the dividend's sign.
def divide(a, b, width, is_signed, remainder):
    a = signed(a, width) if is_signed else a % (1 << width)
    b = signed(b, width) if is_signed else b % (1 << width)
    if b == 0:
        # Both zero-divisor definitions are explicit in the instruction tables.
        return a if remainder else -1
    q = abs(a) // abs(b) * (-1 if (a < 0) != (b < 0) else 1)
    return a - q * b if remainder else q


# Return the selected destination's mathematical result; callers mask it to a register bit pattern.
def oracle(op, a, b, old, x):
    unary = {
        20: lambda: x, 51: lambda: x, 100: lambda: a,
        101: lambda: a.bit_count(), 102: lambda: (a % (1 << 32)).bit_count(),
        103: lambda: 64 - a.bit_length(), 104: lambda: 32 - (a % (1 << 32)).bit_length(),
        105: lambda: len(f'{a:064b}') - len(f'{a:064b}'.rstrip('0')),
        106: lambda: len(f'{a % (1 << 32):032b}') - len(f'{a % (1 << 32):032b}'.rstrip('0')),
        107: lambda: signed(a, 8), 108: lambda: signed(a, 16), 109: lambda: a % 65536,
        110: lambda: int.from_bytes(a.to_bytes(8, 'little'), 'big'),
    }
    if op in unary:
        # Unary and immediate loads do not use the second register.
        return unary[op]() & MASK
    immediate = {
        131: lambda: signed(b+x, 32), 132: lambda: b & x, 133: lambda: b ^ x,
        134: lambda: b | x, 135: lambda: signed(b*x, 32), 136: lambda: b < x,
        137: lambda: signed(b) < signed(x), 138: lambda: signed(b * 2**(x % 32), 32),
        139: lambda: signed((b % 2**32) // 2**(x % 32), 32),
        140: lambda: signed(b, 32) // 2**(x % 32), 141: lambda: signed(x-b, 32),
        142: lambda: b > x, 143: lambda: signed(b) > signed(x),
        144: lambda: signed(x * 2**(b % 32), 32),
        145: lambda: signed((x % 2**32) // 2**(b % 32), 32),
        146: lambda: signed(x, 32) // 2**(b % 32),
        147: lambda: x if b == 0 else old, 148: lambda: x if b != 0 else old,
        149: lambda: b+x, 150: lambda: b*x, 151: lambda: b * 2**(x % 64),
        152: lambda: b // 2**(x % 64), 153: lambda: signed(b) // 2**(x % 64),
        154: lambda: x-b, 155: lambda: x * 2**(b % 64), 156: lambda: x // 2**(b % 64),
        157: lambda: signed(x) // 2**(b % 64), 158: lambda: rotate(b, x, 64),
        159: lambda: rotate(x, b, 64), 160: lambda: signed(rotate(b, x, 32), 32),
        161: lambda: signed(rotate(x, b, 32), 32),
    }
    if op in immediate:
        # Immediates are already decoded independently from their four-byte signed encoding.
        return immediate[op]() & MASK
    binary = {
        190: lambda: signed(a+b, 32), 191: lambda: signed(a-b, 32), 192: lambda: signed(a*b, 32),
        197: lambda: signed(a * 2**(b % 32), 32),
        198: lambda: signed((a % 2**32) // 2**(b % 32), 32),
        199: lambda: signed(a, 32) // 2**(b % 32),
        200: lambda: a+b, 201: lambda: a-b, 202: lambda: a*b,
        207: lambda: a * 2**(b % 64), 208: lambda: a // 2**(b % 64),
        209: lambda: signed(a) // 2**(b % 64),
        210: lambda: a & b, 211: lambda: a ^ b, 212: lambda: a | b,
        213: lambda: (signed(a)*signed(b)) // 2**64, 214: lambda: (a*b) // 2**64,
        215: lambda: (signed(a)*b) // 2**64,
        216: lambda: a < b, 217: lambda: signed(a) < signed(b),
        218: lambda: a if b == 0 else old, 219: lambda: a if b != 0 else old,
        220: lambda: rotate(a, -b, 64), 221: lambda: signed(rotate(a, -b, 32), 32),
        222: lambda: rotate(a, b, 64), 223: lambda: signed(rotate(a, b, 32), 32),
        224: lambda: a & ~b, 225: lambda: a | ~b, 226: lambda: ~(a ^ b),
        227: lambda: max(signed(a), signed(b)), 228: lambda: max(a, b),
        229: lambda: min(signed(a), signed(b)), 230: lambda: min(a, b),
    }
    if op in (193, 194, 195, 196, 203, 204, 205, 206):
        # Explicit signed low-word normalization also handles MIN_INT / -1.
        width = 32 if op < 200 else 64
        result = divide(a, b, width, op in (194, 196, 204, 206), op in (195, 196, 205, 206))
        return (signed(result, 32) if width == 32 else result) & MASK
    return binary[op]() & MASK


# Decode literal integers with bounded shifts; never evaluate upstream code.
def literal(text):
    parts = re.split(r'(<<|>>)', text.strip())
    assert len(parts) in (1, 3, 5)
    assert re.fullmatch(r'-?(?:0x[0-9a-fA-F]+|[0-9]+)', parts[0].strip())
    value = int(parts[0].strip(), 0)
    for offset in range(1, len(parts), 2):
        # Assembly witnesses need only constant shifts within a register width.
        assert re.fullmatch(r'[0-9]+', parts[offset+1].strip())
        shift = int(parts[offset+1].strip())
        assert 0 <= shift < 64
        value = value * 2**shift if parts[offset] == '<<' else value // 2**shift
    return value & MASK


# Locate the pristine assembly fixtures carried in the pinned PolkaVM repository.
def upstream_paths():
    base = ROOT/'vendor/polkavm/guest-programs/riscv-tests/tests'
    return [base/('rv64um' if name.startswith(('mul', 'div', 'rem')) else 'rv64ui')/(name+'.S')
            for name in UPSTREAM]


# Map encoded operands independently of the production decoder, including saturated register bytes.
def record(op, descriptor, destination, x, values, expected=None):
    registers = [100+i for i in range(13)]
    for index, value in zip((0, 1, 2, 12), values):
        # Only four input registers vary; all others are retained sentinel values.
        registers[index] = value
    a, b, d = min(descriptor % 16, 12), min(descriptor // 16, 12), min(destination, 12)
    if 100 <= op <= 110:
        # Unary operands name low D and high A.
        a, d = b, a
    elif op in (20, 51) or 131 <= op <= 161:
        # Both immediate operand families write A.
        d = a
    answer = oracle(op, registers[a], registers[b], registers[d], x)
    if expected is not None:
        # Every imported result must independently agree before becoming a native fixture.
        assert answer == expected, (op, registers[a], registers[b], answer, expected)
    return struct.pack('<BBB6Q', op, descriptor, destination, x, *values, answer)


# Build deterministic edge, alias, randomized and upstream-derived cases without native execution.
def fixtures():
    rows = []
    edge = (0, 1, 2, 31, 32, 63, 64, 127, 255, 0x7fffffff, 0x80000000,
            0xffffffff, 0x100000000, (1 << 63)-1, 1 << 63, MASK)
    state = 0x7261676e61726f6b
    for op in OPS:
        # Every Cartesian edge pair is tested with distinct registers; add explicit alias patterns below.
        pairs = [(a, b, 0x8877665544332211, 0xfedcba9876543210, b) for a in edge for b in edge]
        for _ in range(64):
            # A fixed recurrence avoids platform/library random-sequence differences.
            vals = []
            for _ in range(5):
                state = (state * 6364136223846793005 + 1442695040888963407) & MASK
                vals.append(state)
            pairs.append(tuple(vals))
        for i, (a, b, old, high, imm) in enumerate(pairs):
            x = imm if op == 20 else signed(imm, 32) & MASK
            # Unary and load-immediate cases still span all input edge values.
            descriptor = 0x01 if 100 <= op <= 110 else 0x10
            rows.append(record(op, descriptor, 2, x, (a, b, old, high)))
            if i < len(edge) or i % 17 == 0:
                # Include source equality, either destination alias and saturated register 12.
                for descriptor, destination in ((0x10, 0), (0x10, 1), (0x00, 0), (0xff, 255)):
                    rows.append(record(op, descriptor, destination, x, (a, b, old, high)))
    imported = 0
    for path in upstream_paths():
        # Only TEST_RR_OP records are portable scalar witnesses; other assembly is never executed.
        op = UPSTREAM[path.stem]
        cases = re.findall(r'TEST_RR_OP\(\s*\d+,\s*\w+,\s*([^,]+),\s*([^,]+),\s*([^;)]+)\s*\)', path.read_text())
        assert cases, path
        for expected, a, b in cases:
            rows.append(record(op, 0x10, 2, 0, (literal(a), literal(b), 99, 0), literal(expected)))
            imported += 1
    return b'PVMREG01' + struct.pack('<I', len(rows)) + b''.join(rows), len(rows), imported


# Explicit regeneration writes only the checked-in test fixture, never production source.
if __name__ == '__main__':
    data, count, imported = fixtures()
    (ROOT/'tests/fixtures/pvm-registers.bin').write_bytes(data)
    print(f'{count} cases, including {imported} pinned upstream witnesses')
