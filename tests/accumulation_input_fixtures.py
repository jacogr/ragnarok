# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP accpar/accone invocation oracle and deterministic native fixture transport.

Exposes invocation for arbitrary-precision mathematical gas sums and prepare for mixed round
contexts over the independently prepared pinned/authored report prefixes. No execution is simulated.
"""
import hashlib
import json
import random
from accumulation_operand_fixtures import prepare as operand_prepare
from c2_oracle import BROAD, parse, wire


# Dictionary union/filtering expresses the equations without native descriptor sorting or fixed-width sums.
def invocation(operands, transfers, allowances):
    services = set(operands) | {t[1] for t in transfers} | set(allowances)
    result = []
    # Numeric service enumeration affects only outer order; each inner source sequence remains intact.
    for service in sorted(services):
        selected = [t for t in transfers if t[1] == service]
        reports = operands.get(service, [])
        gas = allowances.get(service, 0) + sum(t[4] for t in selected)
        gas += sum(parse('O', item, BROAD)[2][4] for item in reports)
        result.append((service, gas, len(selected), [wire('T', t) for t in selected]+reports))
    return result


# Extend the original report-prefix transport with explicit independent transfer/free-allowance context.
def prepare(folder):
    original, evidence = operand_prepare(folder)
    rng = random.Random(0x494E505554)
    lines = []
    overflow = 0
    # Reuse every unchanged published/authored report prefix with a new deterministic round context.
    for ordinal, line in enumerate(original.read_text().splitlines()):
        fields = line.split()
        operands = {} if fields[8] == '-' else {
            int(group.split(':')[0]): [bytes.fromhex(x) for x in group.split(':')[1].split(',')]
            for group in fields[8].split(';')}
        ids = [0, 1, 9, 42, 1729, 2**32-1]
        transfers = [(rng.choice(ids), rng.choice(ids), rng.randrange(2**64),
                      bytes([i+ordinal % 128])*128, rng.choice((0, 1, 127, 128, 16384)))
                     for i in range(rng.randrange(9))]
        allowances = {s: rng.choice((0, 1, 128, 100000)) for s in rng.sample(ids, rng.randrange(7))}
        expected = invocation(operands, transfers, allowances)
        bad = any(gas >= 2**64 for _, gas, _, _ in expected)
        overflow += bad
        groups = 'overflow' if bad else ';'.join(
            f'{s}:{gas}:{count}:'+(','.join(x.hex() for x in items) or '-')
            for s, gas, count, items in expected) or '-'
        lines.append(' '.join([*fields[:8], ','.join(wire('T', t).hex() for t in transfers) or '-',
                               ','.join(f'{s}:{allowances[s]}' for s in sorted(allowances)) or '-', groups]))
    path = folder/'accumulation-inputs.txt'
    path.write_text('\n'.join(lines)+'\n')
    evidence = dict(report_context=evidence, cases=len(lines), overflow=overflow,
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'accumulation-inputs.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
