# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP conditional-control fixtures; no production decoder or evaluator is imported."""
import struct
from pathlib import Path

OPS = (*range(81, 91), *range(170, 176))
VALUES = (0, 1, 2, 3, (1 << 64)-1, 1 << 63)


def signed(value):
    """Interpret a fixed register bit pattern as a mathematical two's-complement integer."""
    return value if value < 1 << 63 else value-(1 << 64)


def taken(opcode, left, right):
    """Evaluate the pinned paper's ten immediate and six register predicates directly."""
    if opcode in (81, 170):
        return left == right
    if opcode in (82, 171):
        return left != right
    if opcode in (83, 172):
        return left < right
    if opcode == 84:
        return left <= right
    if opcode in (85, 174):
        return left >= right
    if opcode == 86:
        return left > right
    if opcode in (87, 173):
        return signed(left) < signed(right)
    if opcode == 88:
        return signed(left) <= signed(right)
    if opcode in (89, 175):
        return signed(left) >= signed(right)
    assert opcode == 90
    return signed(left) > signed(right)


def fixtures():
    """Frame literal branches with distinct path writes and three invalid-destination classes."""
    count = len(OPS)*len(VALUES)*4 + 6*4*5 + 6*6*6*3*2
    out = bytearray(b'PVMCTL01'+struct.pack('<I', count))
    for opcode in OPS:
        for left in VALUES:
            for mode in range(4):
                immediate = opcode < 100
                following = 7 if immediate else 6
                destination = following+5
                target = (destination, 1, 3, 127)[mode]
                branch = bytes([opcode, 17, 2, (target-3) & 255]) if immediate else bytes([opcode, 33, (target-3) & 255])
                code = bytes([51, 7, 7])+branch+bytes([51, 8, 21, 50, 0, 51, 8, 42, 50, 0])
                mask = bytearray((len(code)+7)//8)
                for pc in (0, 3, following, following+3, destination, destination+3):
                    mask[pc//8] |= 1 << (pc % 8)
                wire = bytes([0, 0, len(code)])+code+mask
                registers = [0]*13
                registers[0], registers[1], registers[2] = 0xffff0000, left, 2
                registers[7], registers[8] = 99, 99
                expected = registers.copy()
                expected[7] = 7
                if mode == 0:
                    expected[8] = 42 if taken(opcode, left, 2) else 21
                out += struct.pack('<IBI26Q', len(wire), int(mode != 0),
                                   3 if mode else 0xffffffff, *registers, *expected)
                out += wire
    for destination in (0, 1, 7, 8, 12, 15):
        for value in (0, 7, 0x80000000, 0xffffffff):
            for target in (13, 1, 3, 127, -125):
                # Static load/jump writes even when destination validation causes panic.
                code = bytes([51,7,7,80,64+destination])+value.to_bytes(4,'little')
                code += ((target-3) & 0xffffffff).to_bytes(4,'little')+bytes([0])
                wire = bytes([0,0,14])+code+bytes([9,32])
                registers = [0x1020304050607000+i for i in range(13)]
                registers[0] = 0xffff0000
                expected = registers.copy()
                expected[7] = 7
                expected[min(12,destination)] = (value if value < 1 << 31 else value-(1 << 32)) & ((1 << 64)-1)
                out += struct.pack('<IBI26Q',len(wire),1,13 if target == 13 else 3,*registers,*expected)+wire
    for destination in (0, 1, 7, 8, 12, 15):
        for base in (0, 1, 7, 8, 12, 15):
            for initial in (0, 1, 2, 4, 0xffff0000, 0xabcdef0100000002):
                for offset in (0, 1, 0xffffffff):
                    for value in (7, 0x80000000):
                        # Inputs are read before the write, including saturated aliases and upper address bits.
                        code = bytes([51,7,7,180,destination+16*base,4])+value.to_bytes(4,'little')
                        code += offset.to_bytes(4,'little')+bytes([0])
                        wire = bytes([1,1,15,14])+code+bytes([9,64])
                        registers = [0x1020304050607000+i for i in range(13)]
                        registers[0] = 0xffff0000
                        registers[min(12,base)] = initial
                        expected = registers.copy()
                        expected[7] = 7
                        effective = (expected[min(12,base)]+(offset if offset < 1 << 31 else offset-(1 << 32))) & 0xffffffff
                        expected[min(12,destination)] = value if value < 1 << 31 else value-(1 << 32)+(1 << 64)
                        halt = effective == 0xffff0000
                        stop = 0xffffffff if halt else (14 if effective == 2 else 3)
                        out += struct.pack('<IBI26Q',len(wire),int(not halt),stop,*registers,*expected)+wire
    return bytes(out), count


if __name__ == '__main__':
    import sys
    data, count = fixtures()
    Path(sys.argv[1]).write_bytes(data)
    print(f'Independent GP conditional-control fixtures: {count}')
