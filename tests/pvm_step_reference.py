# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent composed gas/arithmetic traces for the register-only single-step boundary.

Exposes test-only operation/fixtures helpers and prepare to write verified native input under build/."""
import random
import struct
from pvm_gas_reference import ROOT, tables, simulate, instruction, blob
from pvm_register_reference import OPS, MASK, oracle, signed


# Build full-width test immediates and keep independently known register roles for the arithmetic oracle.
def operation(op, rng):
    a, b, d = (rng.randrange(16) for _ in range(3))
    x = rng.choice((0, 1, MASK, 0x80000000, 0x7fffffff, rng.getrandbits(64)))
    raw = instruction(op, a, b, d)
    if op == 20:
        # Extended loads use all eight bytes without signed compact narrowing.
        raw = raw[:2]+x.to_bytes(8, 'little')
    elif op == 51 or 131 <= op <= 161:
        # Immediate arithmetic uses a sign-extended four-byte encoded operand.
        raw = raw[:2]+(x & 0xffffffff).to_bytes(4, 'little')
        x = signed(x, 32) & MASK
    a, b, d = min(a, 12), min(b, 12), min(d, 12)
    if op in (20, 51) or 131 <= op <= 161:
        # Both immediate families write A; unary shapes already encode high A and low D.
        d = a
    return raw, (op, a, b, d, x)


# Serialize complete expected CPU traces; no production execution generates any expectation.
def fixtures():
    rng = random.Random(0x53544550)
    definitions = tables()
    scenarios = []
    for op in OPS:
        # Every supported opcode has an unskipped independent execution witness.
        scenarios.append(([operation(op, rng)], 0))
    for _ in range(100):
        # Some traces enter the middle of an uncharged block and must still pay for its prefix.
        body = [operation(rng.choice(OPS), rng) for _ in range(rng.randrange(2, 18))]
        scenarios.append((body, rng.randrange(len(body))))
    # A host call before the entry remains part of the containing block's price despite being skipped.
    scenarios.append(([(instruction(10), None), operation(200, rng)], 1))
    out = bytearray(b'PVMSTEP1'+struct.pack('<I', len(scenarios)))
    for index, (body, entry) in enumerate(scenarios):
        # A preceding block distinguishes containing-block lookup from a scan starting at byte zero.
        prefix = [instruction(0)] if index % 2 else []
        raw = [item[0] for item in body]+[instruction(0)]
        price, cycles = simulate(raw, definitions)
        encoded = blob(raw, prefix)
        pc = len(b''.join(prefix))+sum(len(item[0]) for item in body[:entry])
        registers = [rng.choice((0, MASK, 1 << 63, rng.getrandbits(64))) for _ in range(13)]
        out += struct.pack('<IIQQ13QI', len(encoded), pc, price, cycles, *registers, len(body)-entry)+encoded
        for code, arguments in body[entry:]:
            # Evaluate only the selected instruction from the original register values, including aliases.
            op, a, b, d, x = arguments
            registers[d] = oracle(op, registers[a], registers[b], registers[d], x)
            pc += len(code)
            out += struct.pack('<I13Q', pc, *registers)
    return bytes(out), len(scenarios)


# Generate ephemeral native traces after checking the pinned normative source identity.
def prepare(folder):
    import hashlib
    import json
    from pathlib import Path
    pins = json.loads((ROOT/'spec/pins.json').read_text())['graypaper']
    assert hashlib.sha256((ROOT/pins['path']/'text/pvm.tex').read_bytes()).hexdigest() == pins['source_sha256']['text/pvm.tex']
    data, count = fixtures()
    path = Path(folder)/'pvm-step.bin'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return path, dict(cases=count, fixture_sha256=hashlib.sha256(data).hexdigest())
