# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal GP table extraction and an unbounded, simultaneous-transition gas reference.

Exposes test-only tables, simulation, encoding, fixtures and prepare helpers; reads pinned submodule text
without executing or copying upstream implementation code."""
from pathlib import Path
import random
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
TERMINATORS = {0, 1, 40, 50, *range(80, 91), *range(170, 176), 180}


# Read pinned equations as data; no TeX or upstream implementation is executed.
def tables():
    text = (ROOT/'vendor/graypaper/text/pvm.tex').read_text()
    before, costs = text.split(r'\subsection{Gas Cost Tables}', 1)
    instructions = {}
    # Numeric rows uniquely identify the normative opcode and mutation equation.
    for match in re.finditer(r'^\s*(\d+)&\\token\{([^}]+)\}&', before, re.M):
        end = before.find(r'\bottomrule', match.end())
        following = re.search(r'^\s*\d+&\\token', before[match.end():end], re.M)
        body = before[match.end():match.end()+following.start() if following else end]
        destinations = set(re.findall(r"\\reg'_([ABD])|\\reg_([ABD])'", body))
        destinations = {a or b for a, b in destinations}
        sources = set(re.findall(r"\\reg(?!')_([ABD])(?!')", body))
        instructions[int(match[1])] = (match[2], sources, destinations)
    macros = dict(re.findall(r'\\newcommand\*\{\\(\w+)\}\{([^\n]+)\}', costs))
    rows = dict(re.findall(r'\\token\{([^}]+)\}&(.*?)\\\\', costs))
    assert len(instructions) == len(rows) == 139
    return instructions, macros, rows


# Construct a real byte encoding independently of the native operand decoder.
def instruction(op, a=0, b=1, d=2, displacement=0):
    tail = (displacement & 0xffffffff).to_bytes(4, 'little')
    if op <= 2 or op == 10:
        # Empty immediate host calls are valid.
        return bytes([op])
    if op == 20:
        # The extended immediate is fixed width.
        return bytes([op, a])+bytes(8)
    if 30 <= op <= 33:
        # An empty immediate store still has its width descriptor.
        return bytes([op, 0])
    if op == 40:
        # Static jump offsets are signed four-byte values.
        return bytes([op])+tail
    if 50 <= op <= 90:
        # X is empty for two-immediate shapes; the four-byte Y is the branch displacement.
        return bytes([op, a])+tail
    if 100 <= op <= 110:
        # Unary operations name low D and high A.
        return bytes([op, d + 16*a])
    if 120 <= op <= 175:
        # Arithmetic and branch groups name low A and high B.
        return bytes([op, a + 16*b])+tail
    if op == 180:
        # Both immediate widths are empty for this indirect load-jump.
        return bytes([op, a + 16*b, 0])
    return bytes([op, a + 16*b, d])


# Decode only register names and signed branch targets for the independent model.
def operands(raw):
    op = raw[0]
    first = raw[1] if len(raw) > 1 else 0
    low, high = min(12, first % 16), min(12, first // 16)
    if 100 <= op <= 110:
        # This shape reverses the A and D nibble roles.
        return dict(A=high, B=0, D=low)
    return dict(A=low, B=high, D=min(12, raw[2] % 16) if 190 <= op <= 230 else 0)


# Expand the pinned table's restricted macros without eval or a production cost table.
def cost(raw, code, pc, definitions):
    instructions, macros, rows = definitions
    name, reads, writes = instructions[raw[0]]
    regs = operands(raw)
    sources, destinations = ({regs[r] for r in roles} for roles in (reads, writes))
    row = rows[name]
    # Nested macros terminate at literal columns or one of the three explicit predicates.
    for _ in range(8):
        old = row
        row = re.sub(r'\\finish\{(\d+)\}', lambda m:m[1]+'&1&0&0&0&0&0', row)
        row = re.sub(r'\\ifdstandsrcoverlap(shift)?\{(\d+)\}\{(\d+)\}',
                     lambda m:m[2] if (regs['A'] == regs['D'] if m[1] else bool(sources & destinations)) else m[3], row)
        row = re.sub(r'\\(\w+)', lambda m:macros.get(m[1], m[0]), row)
        if old == row:
            # No unresolved recursive macro is allowed into the numeric parser.
            break
    row = row.replace('$\\mathfrak{m}$', '25')
    if '$\\mathfrak{b}$' in row:
        # Pinned PolkaVM wraps decoded offsets to u32 before pricing the raw target byte.
        target = (pc + int.from_bytes(raw[-4:], 'little', signed=True)) % (1 << 32)
        fetch = lambda at:code[at] if at < len(code) else 0
        latency = 1 if {fetch(pc+len(raw)), fetch(target)} & {0, 2} else 20
        row = row.replace('$\\mathfrak{b}$', str(latency))
    values = tuple(map(int, row.split('&')))
    assert len(values) == 7
    return sources, destinations, values[0], values[1], values[2:]


# Keep all historical entries and dependency sets; cycle updates construct a separate next state.
def simulate(sequence, definitions):
    code = b''.join(sequence)
    pending = list(enumerate(sequence))
    pc, cycles, decode, starts = 0, 0, 4, 5
    resources = [4, 4, 4, 1, 1]
    history = []
    while True:
        # Decode takes priority over issue even when an older instruction is ready.
        active = sum(e['state'] != 'retired' for e in history)
        if pending and active < 32:
            _, raw = pending[0]
            src, dst, latency, slots, units = cost(raw, code, pc, definitions)
            if slots <= decode:
                decode -= slots
                pending.pop(0)
                pc += len(raw)
                if raw[0] == 100:
                    # Rename producer identities without creating a new pipeline entry.
                    for entry in history:
                        entry['writes'] = entry['writes'] | dst if entry['writes'] & src else entry['writes'] - dst
                else:
                    # Capture dependencies from the old mapping before assigning the new writer.
                    dependencies = {i for i, e in enumerate(history) if e['writes'] & src}
                    for entry in history:
                        entry['writes'] -= dst
                    history.append(dict(state='decoding', left=latency, dependencies=dependencies,
                                        writes=dst, units=units))
                if raw[0] in TERMINATORS:
                    # Pricing stops at the first terminator irrespective of its execution target.
                    pending.clear()
                continue
        ready = [i for i, e in enumerate(history) if e['state'] == 'waiting'
                 and all(history[j]['left'] == 0 for j in e['dependencies'])
                 and all(a <= b for a, b in zip(e['units'], resources))]
        if ready and starts:
            # Issue the oldest eligible instruction, retaining resource occupancy across cycles.
            selected = history[ready[0]]
            selected['state'] = 'executing'
            resources = [a-b for a, b in zip(resources, selected['units'])]
            starts -= 1
            continue
        if not pending and not active:
            return max(cycles-3, 1), cycles
        cycles += 1
        assert cycles < 100000
        decode, starts = 4, 5
        updated = []
        # Each entry reads only the previous cycle's states and counters.
        for i, entry in enumerate(history):
            copy = dict(entry)
            if all(e['state'] in ('executed', 'retired') for e in history[:i+1]):
                copy['state'] = 'retired'
            elif entry['state'] == 'decoding':
                copy['state'] = 'waiting'
            elif entry['state'] == 'executing' and entry['left'] == 0:
                copy['state'] = 'executed'
            if entry['state'] == 'executing' and entry['left'] > 0:
                copy['left'] -= 1
                if entry['left'] == 1:
                    # Units become available before the separate executed/retired transitions.
                    resources = [a+b for a, b in zip(resources, entry['units'])]
            updated.append(copy)
        history = updated


# Canonical compact natural, independently serialized for these small fixture lengths.
def natural(value):
    if value < 128:
        return bytes([value])
    width = next(n for n in range(1, 8) if value < 1 << (7*(n+1)))
    return bytes([256-(1 << (8-width))+(value >> (8*width))])+(value % (1 << (8*width))).to_bytes(width, 'little')


# Build a blob with independent instruction markers; prefix permits a nonzero block start.
def blob(sequence, prefix=()):
    instructions = [*prefix, *sequence]
    code = b''.join(instructions)
    bitmap = bytearray((len(code)+7)//8)
    pc = 0
    for raw in instructions:
        # Mark only opcodes; operand bytes deliberately remain inspectable for branch pricing.
        bitmap[pc//8] |= 1 << (pc % 8)
        pc += len(raw)
    return b'\0\0'+natural(len(code))+code+bitmap


# Translate a restricted set of compatible assembly witnesses directly from the pinned submodule.
def upstream_cases():
    text = (ROOT/'vendor/polkavm/crates/polkavm-common/src/simulator.rs').read_text()
    names = ('parallel_simple', 'sequential_simple', 'sequential_decode_limits',
             'resource_limits_mul', 'mul_with_dep', 'register_move', 'empty',
             'cmov_destination_is_part_of_the_dependency_chain',
             'cmov_imm_destination_is_part_of_the_dependency_chain', 'cmov_independent')
    registers = {**{'a'+str(i): i for i in range(6)}, 's0': 6}
    cases = {}
    for name in names:
        # Only the program string of an exact named test is consumed; Rust is never executed.
        body = re.search(r'fn test_'+name+r'\(\) \{(.*?)\n    \}', text, re.S)[1]
        assembly = re.findall(r'"([^"\\]*)"', body)[0]
        sequence = []
        for line in assembly.splitlines():
            # Whitespace carries no instruction semantics in these restricted examples.
            line = line.strip()
            if not line:
                continue
            if line in ('trap', 'fallthrough'):
                # Both terminators have fixed GP costs.
                sequence.append(instruction(0 if line == 'trap' else 1))
                continue
            destination, expression = line.split(' = ')
            destination = registers[destination]
            if ' if ' in expression:
                # Conditional moves retain their old destination as a source dependency.
                value, condition = expression.split(' if ')
                test, literal = condition.split(' == ')
                assert literal == '0'
                sequence.append(instruction(218, registers[value], registers[test], destination)
                                if value in registers else
                                instruction(147, destination, registers[test], displacement=int(value, 0)))
            elif ' + ' in expression or ' * ' in expression:
                # This adapter admits only full-width addition/multiplication and immediate addition.
                left, operator, right = expression.split()
                if right in registers:
                    sequence.append(instruction(200 if operator == '+' else 202,
                                                registers[left], registers[right], destination))
                else:
                    # Numeric right operands occur only in the selected immediate-add witness.
                    assert operator == '+'
                    sequence.append(instruction(149, destination, registers[left], displacement=int(right, 0)))
            elif expression in registers:
                # Copies keep their source/destination relationship for frontend renaming.
                sequence.append(instruction(100, registers[expression], d=destination))
            else:
                # Literal loads select exactly the compact/extended instruction width used upstream.
                value = int(expression, 0)
                op = 51 if -(1 << 31) <= value < (1 << 31) else 20
                raw = instruction(op, destination)
                sequence.append(raw[:2]+(value % (1 << (64 if op == 20 else 32))).to_bytes(8 if op == 20 else 4, 'little'))
        cases[name] = sequence
    return cases


# Generate ephemeral native input after verifying the pinned source identities; no upstream files are copied.
def prepare(folder):
    import hashlib
    import json
    from dependencies import require_submodule
    pins = json.loads((ROOT/'spec/pins.json').read_text())['graypaper']
    assert hashlib.sha256((ROOT/pins['path']/'text/pvm.tex').read_bytes()).hexdigest() == pins['source_sha256']['text/pvm.tex']
    upstream = json.loads((ROOT/'spec/polkavm-pins.json').read_text())
    path = require_submodule(upstream)
    for name in ('crates/polkavm-common/src/simulator.rs', 'LICENSE-MIT'):
        # Full source hashes prevent accepting modified upstream examples or notices.
        assert hashlib.sha256((path/name).read_bytes()).hexdigest() == upstream['source_sha256'][name]
    data, count = fixtures()
    target = Path(folder)/'pvm-gas.bin'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    return target, dict(cases=count, fixture_sha256=hashlib.sha256(data).hexdigest())


# Freeze opcode/aliasing coverage, resource saturation, long buffers and deterministic mixed blocks.
def fixtures():
    definitions = tables()
    cases = list(upstream_cases().values())
    for op in definitions[0]:
        # All opcodes get distinct sources, each destination alias and saturated register operands.
        for a, b, d in ((0, 1, 2), (0, 1, 0), (0, 1, 1), (12, 12, 12), (15, 15, 15)):
            cases.append([instruction(op, a, b, d), instruction(0)])
    for op in definitions[0]:
        # Long producers expose source dependencies; subsequent consumers expose overwritten destinations.
        for producer in (0, 1, 2, 12):
            cases.append([instruction(203, 10, 11, producer), instruction(op),
                          instruction(202, 0, 1, 3), instruction(202, 2, 12, 4), instruction(0)])
    for length in (4, 5, 31, 32, 33, 64, 97):
        # Long leading host calls fill the buffer while younger independent operations finish.
        cases.append([instruction(10)]+[instruction(51, a=n % 13) for n in range(length)]+[instruction(0)])
        cases.append([instruction(10)]+[instruction(100, a=n % 13, d=(n+1) % 13) for n in range(length)]+[instruction(0)])
        for op in (105, 124, 120, 202, 203):
            # Exercise each limited resource and destination renaming across many buffer compactions.
            cases.append([instruction(op, a=n % 13, b=(n+1) % 13, d=(n+2) % 13) for n in range(length)]+[instruction(0)])
    rng = random.Random(0x0800)
    regular = sorted(set(definitions[0])-TERMINATORS)
    for _ in range(400):
        # Random bodies remain valid single blocks and never rely on execution values.
        cases.append([instruction(rng.choice(regular), *(rng.randrange(13) for _ in range(3)))
                      for _ in range(rng.randrange(1, 70))]+[instruction(rng.choice(sorted(TERMINATORS)))])
    for marker in (0, 2, 51):
        # Positive branch targets cover raw unmarked operand bytes and the zero suffix.
        for displacement in (0, 1, 2, 6, 7, 100000):
            cases.append([instruction(170, a=marker % 13, displacement=displacement), instruction(marker), instruction(0)])
    for op in [*range(81, 91), *range(170, 176)]:
        # A noncheap fallthrough makes the wrapped absent target itself determine the cheap branch latency.
        for displacement in (-1, -128, -(1 << 31)):
            cases.append([instruction(op, displacement=displacement), instruction(100), instruction(0)])
    for target in (0, 1, 2, 3, 4, 8, 9, 100):
        # Grey issue155: an unreachable jump must not split the earlier load/store gas block.
        cases.append([bytes([51, 7, 7]), bytes([59, 7, 0, 0, 3]), bytes([0]),
                      instruction(40, displacement=target-9)])
    out = bytearray(b'PVMGAS01'+struct.pack('<I', len(cases)))
    for index, sequence in enumerate(cases):
        # Relocate alternate blocks behind a completed trap; pricing depends on relative raw targets.
        prefix = [instruction(0)] if index % 2 else []
        price, cycles = simulate(sequence, definitions)
        encoded = blob(sequence, prefix)
        out += struct.pack('<IQQI', len(b''.join(prefix)), price, cycles, len(encoded))+encoded
    return bytes(out), len(cases)
