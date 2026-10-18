# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent incoming-credit metadata/root witnesses and pinned live-recipient balance projections.

prepare emits test transport only: it neither executes bootstrap-service commands nor simulates PVM/STF.
"""
import hashlib
import json
import random
from state_accounts_oracle import key, wire
from state_layout_oracle import chapter_key
from state_service_values_oracle import blob
from state_trie_oracle import tree


# Bind arbitrary metadata and unrelated entries to independently computed complete embedding-map roots.
def row(name, service, source, amounts, expected_balance):
    before = wire(source)
    after = before[:33]+expected_balance.to_bytes(8, 'little')+before[41:]
    entries = [(key(service), before), (chapter_key(250), b'opaque')]
    prior, _ = tree(entries)
    posterior, _ = tree([(key(service), after), entries[1]])
    return ' '.join((name, str(service), before.hex(), after.hex(), prior.hex(), posterior.hex(),
                     ','.join(map(str, amounts))))


# Published commands expose a literal transfer amount and recipient; retain only their balance projection.
def published():
    result = []
    # Both populations carry the same live-recipient scenario at the pinned vector revision.
    for chain in ('tiny', 'full'):
        data = blob(f'stf/accumulate/{chain}/transfer_for_live_service-1.json')
        command = bytes.fromhex(data['input']['reports'][0]['results'][0]['result']['ok'][2:])
        assert command[:2] == b'\x01\x02' and len(command) == 152
        service = int.from_bytes(command[2:6], 'little')
        amount = int.from_bytes(command[6:14], 'little')
        original = next(a['data']['service'] for a in data['pre_state']['accounts'] if a['id'] == service)
        final = next(a['data']['service'] for a in data['post_state']['accounts'] if a['id'] == service)
        assert service == 1 and amount == 100 and final['balance'] == original['balance']+amount
        source = (bytes.fromhex(original['code_hash'][2:]),
                  tuple(original[k] for k in ('balance', 'min_item_gas', 'min_memo_gas', 'bytes', 'deposit_offset')),
                  tuple(original[k] for k in ('items', 'creation_slot', 'last_accumulation_slot', 'parent_service')))
        result.append(row(chain, service, source, [amount], final['balance']))
    return result


# Seeded authored arithmetic uses Python's unbounded naturals and an independent byte/trie reference.
def prepare(folder):
    lines = published()
    rng = random.Random(0x435245444954)
    # Include zero, maximal single credit, exact maximal aggregate, and nontrivial ordered sequences.
    for index, amounts in enumerate(([0], [2**64-1], [1, 2**64-2], [7, 0, 13],
                                     *([rng.randrange(2**48) for _ in range(8)] for _ in range(32)))):
        balance = 0 if index < 3 else rng.randrange(2**48)
        source = (bytes(rng.randrange(256) for _ in range(32)),
                  (balance, 17, 19, 23, 29), (31, 37, 41, 43))
        lines.append(row(f'authored-{index}', 42, source, amounts, balance+sum(amounts)))
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'accumulation-credit.txt'
    path.write_text('\n'.join(lines)+'\n')
    evidence = {'fixture_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'published_balance_projections': 2, 'authored_contexts': len(lines)-2}
    (folder/'accumulation-credit.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
