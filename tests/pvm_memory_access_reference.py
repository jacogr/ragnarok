# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP scalar memory equations and literal encodings for two-page access fixtures.

Expected registers, first denied page and successful write bytes use mathematical integers;
no production decoder, memory implementation or PolkaVM assembler supplies expectations.
"""
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MASK = (1 << 64)-1
OPS = (*range(30, 34), *range(52, 63), *range(70, 74), *range(120, 131))
HEADER = struct.Struct('<IBIIBBBBB8s26Q')
ADDRESSES = (0x10000, 0x10ff8, 0x10ffc, 0x10fff, 0x11000)


# Unequal byte positions expose endian mistakes, with both signs at each loaded width.
def memory_byte(index, seed):
    return ((index*37+seed) ^ (index >> 4)) & 255


# Apply the paper's finite-width sign interpretation using unbounded mathematical integers.
def sign(value, bits):
    return value-(1 << bits) if value & (1 << (bits-1)) else value


# Encode one fixed-width instruction independently, preserving raw saturated register nibbles.
def witness(op, address, mappings, variant):
    a, b = ((7, 8), (7, 7), (15, 15))[variant]
    ra, rb = min(a, 12), min(b, 12)
    registers = [(0x0123456789abcdef+i*0x101010101010101) & MASK for i in range(13)]
    registers[0] = 0xffff0000
    displacement = (0, 1, -1)[variant]
    y = (0, 0x80000001, 0xffffffff)[variant]
    indirect = op >= 70
    loading = 52 <= op <= 58 or op >= 124
    if indirect:
        # High register bits must not change physical address calculation; aliases use original values.
        base = ra if op < 74 else rb
        registers[base] = (0xfedcba98 << 32) | ((address-displacement) & 0xffffffff)
    x = displacement if indirect else address
    encoded_x = (x & 0xffffffff).to_bytes(4, 'little')
    if op <= 33:
        # Two-immediate shape has an explicit four-byte X width.
        raw = bytes((op, 4))+encoded_x+y.to_bytes(4, 'little')
        width = 1 << (op-30)
        stored = sign(y, 32) & MASK
    elif op <= 62:
        # Direct scalar loads/stores use A and a single signed address immediate.
        raw = bytes((op, a))+encoded_x
        width = 1 << ((op-52)//2) if loading else 1 << (op-59)
        stored = registers[ra]
    elif op <= 73:
        # Indirect immediate stores encode A in the low nibble and X width in the high nibble.
        raw = bytes((op, a+64))+encoded_x+y.to_bytes(4, 'little')
        width = 1 << (op-70)
        stored = sign(y, 32) & MASK
    else:
        # Indirect register forms use original B for the address, including A/B aliases.
        raw = bytes((op, a+16*b))+encoded_x
        width = 1 << ((op-124)//2) if loading else 1 << (op-120)
        stored = registers[ra]
    seed = (0, 128, 255)[variant]
    expected = registers.copy()
    denied = [at//4096*4096 for at in range(address, address+width)
              if mappings[(at-0x10000)//4096] == 0
              or (not loading and mappings[(at-0x10000)//4096] == 2)]
    fault = min(denied) if denied else 0
    writes = bytes(8)
    write_length = 0
    if not fault:
        # No register or memory mutation occurs until the complete access has passed preflight.
        if loading:
            value = sum(memory_byte(at-0x10000, seed) << (8*i)
                        for i, at in enumerate(range(address, address+width)))
            if op in (53, 55, 57, 125, 127, 129):
                value = sign(value, 8*width) & MASK
            expected[ra] = value
        else:
            write_length = width
            writes = stored.to_bytes(8, 'little')
    code = raw+b'\x00'
    mask = bytearray((len(code)+7)//8)
    for pc in (0, len(raw)):
        # The following real trap lets the public interpreter observe successful memory completion.
        mask[pc//8] |= 1 << (pc % 8)
    blob = bytes((0, 0, len(code)))+code+mask
    return HEADER.pack(len(blob), 2 if fault else 0, fault, address, width,
                       *mappings, seed, write_length, writes, *registers, *expected)+blob


# Cover all scalar forms, all two-page permissions and three original-register/immediate variants.
def fixtures():
    rows = [witness(op, address, (first, second), variant)
            for op in OPS for address in ADDRESSES for first in range(3)
            for second in range(3) for variant in range(3)]
    return b'PVMMAC01'+struct.pack('<I', len(rows))+b''.join(rows), len(rows)


# Explicit regeneration changes only the owned frozen corpus; normal tests never rewrite inputs.
if __name__ == '__main__':
    data, count = fixtures()
    (ROOT/'tests/fixtures/pvm-memory-access.bin').write_bytes(data)
    print(f'{count} scalar memory access witnesses')
