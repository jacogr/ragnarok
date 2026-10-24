# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent entered-block gas/prefix observations for the unchanged tiny control corpus."""
import hashlib
import json
import struct
from pathlib import Path
from pvm_control_reference import fixtures as control_fixtures, taken
from pvm_gas_reference import tables, simulate, TERMINATORS

ROOT = Path(__file__).resolve().parents[1]
MASK = (1 << 64)-1
CONTROL = struct.Struct('<IBI26Q')
ROW = struct.Struct('<BQB')
BLOCK = struct.Struct('<IQ13Q')


def immediate(raw):
    """Interpret a bounded literal little-endian operand with infinite zero suffix semantics."""
    return int.from_bytes(raw[:4], 'little', signed=True) if raw else 0


def observe(wire, initial, definitions):
    """Follow only the independently encoded control subset, recording charged-block prefixes before mutation."""
    count, width, length = wire[:3]
    assert count <= 1 and width <= 1 and 0 < length < 64
    offset = 3+count*width
    code, bitmap = wire[offset:offset+length], wire[offset+length:]
    starts = [pc for pc in range(length) if bitmap[pc//8] & (1 << (pc%8))]
    parts = [code[pc:(starts[i+1] if i+1 < len(starts) else length)]
             for i, pc in enumerate(starts)]
    decoded = dict(zip(starts, parts))
    boundaries = {0}
    for i, raw in enumerate(parts[:-1]):
        # Only marked terminators create sequential block boundaries; their operand bytes never do.
        if raw[0] in TERMINATORS:
            boundaries.add(starts[i+1])
    registers, pc, paid, steps, blocks = list(initial), 0, False, 0, []
    while steps < 4:
        assert pc in decoded
        if not paid:
            index = starts.index(pc)
            # Passing the remaining partitions preserves the full raw target-byte context; the simulator stops at the first terminator.
            charge, _ = simulate(parts[index:], definitions, prefix=parts[:index])
            blocks.append((pc, charge, *registers))
            paid = True
        raw = decoded[pc]
        opcode = raw[0]
        following = pc+len(raw)
        steps += 1
        if opcode == 0:
            # The frozen public interpreter reports the causing trap PC.
            return registers, 1, pc, steps, blocks
        if opcode == 51:
            # The common prefix/path marker is an immediate assignment with sign extension.
            registers[min(raw[1]%16, 12)] = immediate(raw[2:]) & MASK
            pc = following
            continue
        a = min(raw[1]%16, 12)
        # Static and conditional targets must name genuine block starts before selecting a predicate path.
        if opcode in (*range(81, 91), *range(170, 176), 80):
            if opcode < 100:
                # Immediate and register predicates use their separately encoded operand shapes.
                xlen = min(4, (raw[1]//16)%8)
                right = immediate(raw[2:2+xlen]) & MASK
                displacement = immediate(raw[2+xlen:])
            else:
                # Register comparisons read both original saturated register positions.
                right = registers[min(raw[1]//16, 12)]
                displacement = immediate(raw[2:])
            target = pc+displacement
            if opcode == 80:
                # A load/jump retains its assignment even when destination validation panics.
                registers[a] = right
            # Invalid targets panic even when a conditional would choose fallthrough.
            if target not in boundaries or (opcode != 80 and following not in boundaries):
                return registers, 1, pc, steps, blocks
            pc = target if opcode == 80 or taken(opcode, registers[a], right) else following
            paid = False
            continue
        assert opcode in (50, 180)
        if opcode == 180:
            # Read the full original base/offset before the potentially aliased destination assignment.
            xlen = min(4, raw[2]%8)
            value, displacement = immediate(raw[3:3+xlen]) & MASK, immediate(raw[3+xlen:])
            address = (registers[min(raw[1]//16, 12)]+displacement) & 0xffffffff
            registers[a] = value
        else:
            # The path-ending dynamic jump reads A with its optional signed offset.
            address = (registers[a]+immediate(raw[2:])) & 0xffffffff
        if address == 0xffff0000:
            # Halt has precedence over zero/odd/table/destination validation.
            return registers, 0, 0xffffffff, steps, blocks
        ordinal = address//2-1
        # JAM zero-width tables expose no executable entries.
        if address == 0 or address%2 or ordinal < 0 or ordinal >= count or width == 0:
            return registers, 1, pc, steps, blocks
        target = int.from_bytes(wire[3+ordinal*width:3+(ordinal+1)*width], 'little')
        if target not in boundaries:
            # Operand/out-of-code targets preserve the causing instruction and explicit load mutation.
            return registers, 1, pc, steps, blocks
        pc, paid = target, False
    raise AssertionError('independent control trace did not terminate in four instructions')


def fixtures():
    """Append a gas/prefix companion without replacing any original control bytes or expected state."""
    original, count = control_fixtures()
    definitions = tables()
    out, cursor = bytearray(b'PVMCPR01'+struct.pack('<I', count)), 12
    for _ in range(count):
        header = CONTROL.unpack_from(original, cursor)
        wire = original[cursor+CONTROL.size:cursor+CONTROL.size+header[0]]
        registers, exit, pc, steps, blocks = observe(wire, header[3:16], definitions)
        assert tuple(registers) == header[16:29] and (exit, pc) == header[1:3]
        assert 1 <= len(blocks) <= 2 and 1 <= steps <= 4
        out += ROW.pack(steps, sum(block[1] for block in blocks), len(blocks))
        for block in blocks:
            out += BLOCK.pack(*block)
        cursor += CONTROL.size+header[0]
    assert cursor == len(original)
    return bytes(out), count


# Explicit regeneration owns only the new companion; ordinary tests never rewrite frozen bytes.
if __name__ == '__main__':
    data, count = fixtures()
    target = ROOT/'tests/fixtures/pvm-control-pricing.bin'
    target.write_bytes(data)
    descriptor = dict(environment='RAGNAROK_PVM_CONTROL_PRICING',
        files={target.name: hashlib.sha256(data).hexdigest()}, target=target.name)
    (target.parent/'pvm_control_pricing.fixture.json').write_text(json.dumps(descriptor, indent=2)+'\n')
    print('Independent control pricing companions:', count)
