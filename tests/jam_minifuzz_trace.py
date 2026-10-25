# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Author upstream minifuzz file pairs from independent current-profile whole-map STF answers."""
import hashlib
import json
from pathlib import Path
from state_layout_oracle import digest

PEER_REQUEST = b'\x00\x01'+(3).to_bytes(4, 'little')+bytes([0, 8, 0])+bytes(3)+b'\x04test'
PEER_RESPONSE = b'\x00\x01'+(3).to_bytes(4, 'little')+bytes([0, 8, 0])+bytes(3)+b'\x08Ragnarok'


def exchanges(job):
    """Calculate every raw request/reply before execution; no target byte becomes an expected answer."""
    result = [(PEER_REQUEST, PEER_RESPONSE), (job['initialize'], b'\x02'+job['state'][:32]),
              (b'\x04'+digest(job['header']), b'\x05'+job['state'][32:])]
    sibling = None
    for step in job['steps']:
        header = step['block'][:297]
        result.extend(((b'\x03'+step['block'], b'\x02'+step['state'][:32]),
                       (b'\x04'+digest(header), b'\x05'+step['state'][32:])))
        if step['kind'] == 'V':
            sibling = header, step['state'] # Original-last publication must preserve this independent variant map.
        elif sibling is not None:
            result.append((b'\x04'+digest(sibling[0]), b'\x05'+sibling[1][32:]))
            sibling = None
    assert sibling is None and job['steps']
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
