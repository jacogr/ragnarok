# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Original dependent register programs with independent arithmetic and GP pipeline checkpoints."""
import struct
from pathlib import Path
from pvm_register_reference import OPS, MASK, oracle
from pvm_gas_reference import blob, simulate, tables

ROOT = Path(__file__).resolve().parents[1]
HEADER = struct.Struct('<III13Q')
BLOCK = struct.Struct('<IQQ')
CHECK = struct.Struct('<IIQ13Q')
EDGES = (0, 1, MASK, 1 << 63, (1 << 63)-1, 0xffffffff, 0x80000000,
         0x100000000, 31, 32, 63, 64, 0x8877665544332211)


# Each program executes every register opcode exactly once with a different dependency/order pattern.
def programs():
    definitions = tables()
    for seed, stride in enumerate((1, 2, 3, 4, 6, 7, 8, 9)):
        registers = [EDGES[(i+seed) % 13] for i in range(13)]
        initial = registers.copy()
        sequence, blocks, checkpoints, opcodes = [], [], [], []
        pc, previous, start, charged = 0, seed, 0, 0
        for group in range(5):
            # Seventeen dependent mutations and their observations share one immutable gas block.
            body, observed = [], []
            for offset in range(17):
                i = group*17+offset
                op = OPS[(i*stride+seed*11) % len(OPS)]
                a, b = previous, (previous+1+seed) % 13
                d = a if i % 3 == 0 else (i*7+seed) % 13
                x = (-2147483648, -1, 0, 1, 31, 32, 63, 64)[(i+seed) % 8] & MASK
                if op == 20:
                    # Extended loads use all eight literal bytes independently of compact sign extension.
                    x = EDGES[(i+seed) % 13]
                    raw = bytes((op, d))+x.to_bytes(8, 'little')
                    a = d
                elif op == 51 or 131 <= op <= 161:
                    # Compact immediate destinations occupy low A; B carries the preceding result.
                    b = previous
                    a = d
                    raw = bytes((op, d if op == 51 else d+16*b))+(x & 0xffffffff).to_bytes(4, 'little')
                elif 100 <= op <= 110:
                    # The unary descriptor reverses the source/destination roles.
                    raw = bytes((op, d+16*a))
                else:
                    # Three-register descriptors keep D in its common paper/JAM low-byte domain.
                    raw = bytes((op, a+16*b, d))
                old = registers[d]
                registers[d] = oracle(op, registers[a], registers[b], old, x)
                body.extend((raw, bytes((10, 13))))
                pc += len(raw)
                observed.append((pc, registers.copy()))
                pc += 2
                previous = d
                opcodes.append(op)
            body.append(bytes((1 if group < 4 else 0,)))
            pc += 1
            price, cycles = simulate(body, definitions)
            charged += price
            blocks.append((start, price, cycles))
            checkpoints.extend((where, start, charged, *values) for where, values in observed)
            sequence.extend(body)
            start = pc
        yield dict(initial=initial, blocks=blocks, checkpoints=checkpoints,
                   wire=blob(sequence), opcodes=opcodes, sequence=sequence)


# Framing retains complete inputs, block prices and every full-register checkpoint without engine output.
def fixtures():
    records = []
    for row in programs():
        wire, blocks, checks = row['wire'], row['blocks'], row['checkpoints']
        records.append(HEADER.pack(len(wire), len(blocks), len(checks), *row['initial'])+
                       b''.join(BLOCK.pack(*block) for block in blocks)+
                       b''.join(CHECK.pack(*check) for check in checks)+wire)
    return b'PVMCHN01'+struct.pack('<I', len(records))+b''.join(records), len(records)


# Explicit regeneration is separate from test execution and updates only this project's original fixture.
if __name__ == '__main__':
    data, count = fixtures()
    (ROOT/'tests/fixtures/pvm-register-chains.bin').write_bytes(data)
    print(f'{count} dependent programs with 85 checkpoints each')
