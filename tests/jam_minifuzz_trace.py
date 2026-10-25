# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Author upstream minifuzz file pairs from independent current-profile whole-map STF answers."""
import hashlib
import json
from pathlib import Path
from state_layout_oracle import digest

PEER_REQUEST = b'\x00\x01'+(3).to_bytes(4, 'little')+bytes([0, 8, 0])+bytes(3)+b'\x04test'
PEER_RESPONSE = b'\x00\x01'+(3).to_bytes(4, 'little')+bytes([0, 8, 0])+bytes(3)+b'\x08Ragnarok'


def retained_sibling_queries(job):
    """Count independently required original-last queries from the explicitly declared finite sibling window."""
    capacity = job.get('fork_capacity',2)
    assert type(capacity) is int and 1 <= capacity <= 64
    pending = total = 0
    for step in job['steps']:
        if step['kind'] == 'V': pending = min(pending+1,capacity) # Every variant occupies one retained position.
        elif pending:
            total += min(pending,capacity-1);pending = 0 # Original-last itself consumes the newest position.
    assert pending == 0
    return total


def exchanges(job):
    """Calculate every raw request/reply before execution; no target byte becomes an expected answer."""
    result = [(PEER_REQUEST, PEER_RESPONSE), (job['initialize'], b'\x02'+job['state'][:32]),
              (b'\x04'+digest(job['header']), b'\x05'+job['state'][32:])]
    siblings = []
    capacity = job.get('fork_capacity',2)
    assert type(capacity) is int and 1 <= capacity <= 64
    for step in job['steps']:
        header = step['header']
        result.extend(((b'\x03'+step['block'], b'\x02'+step['state'][:32]),
                       (b'\x04'+digest(header), b'\x05'+step['state'][32:])))
        if step['kind'] == 'V':
            siblings = (siblings+[(header,step['state'])])[-capacity:] # Keep only independently known retained maps.
        elif siblings:
            retained = siblings[-(capacity-1):] if capacity > 1 else []
            for header,state in retained:
                result.append((b'\x04'+digest(header),b'\x05'+state[32:]))
            siblings = []
    assert not siblings and job['steps']
    result.append((b'\x04'+digest(job['header']), b'\x05'+job['state'][32:]))
    return result


def write_trace(folder, pairs):
    """Materialize only complete independently prepared file pairs and their immutable hashes."""
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    if list(folder.iterdir()):
        raise ValueError('Minifuzz trace directory must be fresh')
    kinds = {0: 'peer_info', 1: 'initialize', 2: 'state_root', 3: 'import_block', 4: 'get_state', 5: 'state'}
    files = {}
    for index, (request, reply) in enumerate(pairs):
        for side, data in (('fuzzer', request), ('target', reply)):
            if not data or len(data) > 16777216:
                raise ValueError('Minifuzz message exceeds bounds')
            name = f'{index:08d}_{side}_{kinds[data[0]]}.bin'
            (folder/name).write_bytes(data)
            files[name] = hashlib.sha256(data).hexdigest()
    (folder/'manifest.json').write_text(json.dumps(dict(pairs=len(pairs), files=files), indent=2)+'\n')
    return files
