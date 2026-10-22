# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent dictionary reference for sparse full-domain supervisor identities and incarnation selection."""
from pathlib import Path
import itertools
import struct
IDS=(0,17,(1<<32)-1)
CREATED=(0,1,(1<<32)-1)
ROWS=512

def records():
    """Enumerate all nomination choices and independently matching/stale creation expectations."""
    output=[]
    for choices in itertools.product(range(4),repeat=3):
        for mask in range(8):
            fields=[]
            for target,choice in enumerate(choices):
                nominee=IDS[choice] if choice<3 else 99
                actual=CREATED[choice] if choice<3 else 0
                expected=actual ^ ((mask>>target)&1)
                dictionary=dict(zip(IDS,CREATED))
                if nominee not in dictionary:
                    effective,decision=IDS[target],1 # Complete dictionary absence falls back to self.
                elif dictionary[nominee]!=expected:
                    effective,decision=IDS[target],2 # A reused identity cannot inherit another incarnation's authority.
                else:
                    effective,decision=nominee,0 # Exactly one direct designated identity, no recursion.
                fields.extend((IDS[target],CREATED[target],nominee,expected,effective,decision))
            output.append(tuple(fields))
    return output

def encoded():
    """Full-width test words carry exact E4 inputs/outputs without another production wire schema."""
    return ''.join(struct.pack('<18Q',*row).hex()+'\n' for row in records()).encode()

if __name__=='__main__':
    # Explicit fixture regeneration is independent of production lookup/sorting code.
    (Path(__file__).parent/'fixtures/supervision-corpus.txt').write_bytes(encoded())
