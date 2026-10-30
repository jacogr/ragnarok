#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Derive literal fixture prices from the independent pinned-GP oracle; no native code runs."""
import inspect
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests'))
import pvm_gas_reference as reference

source = inspect.getsource(reference.simulate)
anchor = '    while True:\n'
assert source.count(anchor) == 1
prune = '''    while True:
        # Retired prefix entries have no occupied units or unresolved dependency; compact only their indices.
        retired = 0
        while retired < len(history) and history[retired]['state'] == 'retired':
            retired += 1
        if retired:
            history = history[retired:]
            for entry in history:
                entry['dependencies'] = {index-retired for index in entry['dependencies'] if index >= retired}
'''
namespace = dict(reference.__dict__)
exec(compile(source.replace(anchor, prune), '<independent-retired-prefix-oracle>', 'exec'), namespace)
bounded = namespace['simulate']
definitions = reference.tables()


def blocks(markers):
    """Literal source/targets match the fixture's separate long and eligible two-block loops."""
    a = [bytes([2])]*markers+[bytes([149, 0, 1])]*4+[bytes([172, 0x10, 6, 0, 0, 0])]
    back = markers+30
    b = [bytes([149, 0x22, 1])]*4+[bytes([172, 0x10])+(-back & 0xffffffff).to_bytes(4, 'little')]
    small = [bytes([149, 0, 1]), bytes([172, 0x10, 6, 0, 0, 0])]
    tail = [bytes([149, 0, 1]), bytes([172, 0x10, 0xf4, 0xff, 0xff, 0xff])]
    return [a, b, small, tail, [bytes([0])]]


trials = 0
for markers in (0, 1, 2, 7, 16, 31, 32, 33, 63, 64):
    # Prove exact old/new oracle prices and cycle counts across active-window boundaries before using a long input.
    sequence = blocks(markers)
    prefix = []
    for index, body in enumerate(sequence):
        suffix = [raw for block in sequence[index:] for raw in block]
        assert bounded(suffix, definitions, prefix) == reference.simulate(suffix, definitions, prefix)
        trials += 1
        prefix += body

sequence = blocks(4096)
prefix, results = [], []
for index, body in enumerate(sequence):
    # The complete following bytes matter to branch pricing, even though simulation stops at this terminator.
    suffix = [raw for block in sequence[index:] for raw in block]
    price, cycles = bounded(suffix, definitions, prefix)
    results.append(dict(pc=sum(map(len, prefix)), instructions=len(body), gas=price, cycles=cycles))
    prefix += body
receipt = dict(status='PASS', unchanged_oracle_crosschecks=trials, blocks=results,
    native_execution=False, change='Discard only fully retired prefix and remap remaining dependency indices; production oracle/source unchanged.')
(Path(__file__).parent/'gas-oracle.json').write_text(json.dumps(receipt, indent=2)+'\n')
print(json.dumps(receipt))
