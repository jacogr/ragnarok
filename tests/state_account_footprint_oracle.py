# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent unbounded integer account item/octet reference for full-width differential fixtures."""
from pathlib import Path
import random
import struct
MAX=(1<<64)-1
ITEMS=(1<<32)-1
ROWS=2048

def observation(values):
    """Compute both direct mathematical equations before testing their distinct output widths."""
    storage, requests, keys, values, advertised = values
    items=storage+2*requests
    octets=34*storage+81*requests+keys+values+advertised
    overflow=items>ITEMS or octets>MAX
    return (0 if overflow else items, 0 if overflow else octets, int(overflow))

def cases():
    """Keep authored exact/one-over boundaries and reproducible sparse/full-width shapes."""
    values=[(0,0,0,0,0),(2,3,5,7,11),(1,1,2,1,3),(1,ITEMS//2,0,0,0),
            (0,0,MAX,0,0),(0,0,MAX,1,0),(ITEMS,0,0,0,0),(ITEMS+1,0,0,0,0),
            (0,0,0,MAX,0),(0,0,0,0,MAX),(0,0,0,1,MAX)]
    rng=random.Random(0xf007)
    edges=[0,1,2,ITEMS//2,ITEMS,ITEMS+1,MAX//81,MAX//34,MAX-1,MAX]
    while len(values)<ROWS:
        mode=len(values)%4
        if mode==0:
            row=tuple(rng.randrange(1000) for _ in range(5))
        elif mode==1:
            row=(rng.randrange(4),rng.randrange(4),rng.getrandbits(64),0,0)
        elif mode==2:
            row=tuple(rng.choice(edges) for _ in range(5))
        else:
            row=tuple(rng.getrandbits(64) for _ in range(5))
        values.append(row)
    return values

def encoded():
    """Seven full-width words and one overflow flag form deterministic test-only transport."""
    return ''.join(struct.pack('<7QB',*row,*observation(row)).hex()+'\n' for row in cases()).encode()

if __name__=='__main__':
    # Explicit deterministic fixture regeneration never invokes production codecs.
    (Path(__file__).parent/'fixtures/account-footprint-corpus.txt').write_bytes(encoded())
