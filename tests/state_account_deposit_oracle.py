# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent Python integer reference for exact account minimums and dual-pool coverage."""
from pathlib import Path
import random
import struct
MAX = (1 << 64)-1
ROWS = 1024

def observation(values):
    """Evaluate the mathematical equation before checking its output domain."""
    items, octets, gratis, base, item, octet, liquid, protected = values
    minimum = max(0, base + item*items + octet*octets - gratis)
    overflow = minimum > MAX
    return (0 if overflow else minimum, int(overflow), int(not overflow and liquid+protected >= minimum))

def cases():
    """Mix independently authored cancellation witnesses with reproducible small/full-width inputs."""
    values = [
        (3,121,20,100,2,3,449,0), (0,0,MAX,MAX,0,0,0,0),
        (2,0,MAX,0,MAX,0,MAX,MAX), (3,0,MAX,0,MAX,0,MAX,MAX),
        (1,0,1,MAX,1,0,1,MAX), (0,2,MAX,0,0,MAX,0,MAX),
        (0,3,MAX,0,0,MAX,MAX,MAX), (0,MAX,MAX,MAX,0,1,MAX,0),
        ((1<<32)-1,MAX,MAX,MAX,MAX,MAX,MAX,MAX), (0,0,0,0,0,0,0,0)]
    rng = random.Random(0xacc0de)
    while len(values) < ROWS:
        mode = len(values)%4
        if mode == 0:
            row = (rng.randrange(16),rng.randrange(100000),rng.randrange(1000),rng.randrange(100),rng.randrange(8),rng.randrange(8),rng.randrange(1000),rng.randrange(1000))
        elif mode == 1:
            row = (0,rng.getrandbits(64),rng.getrandbits(64),rng.getrandbits(64),0,1,rng.getrandbits(64),rng.getrandbits(64))
        elif mode == 2:
            row = (rng.randrange(4),0,MAX,0,MAX,0,rng.getrandbits(64),rng.getrandbits(64))
        else:
            row = (rng.getrandbits(32),rng.getrandbits(64),rng.getrandbits(64),rng.getrandbits(64),rng.getrandbits(64),rng.getrandbits(64),rng.getrandbits(64),rng.getrandbits(64))
        values.append(row)
    return values

def encoded():
    """Fixed little-endian words and two exact flags are test transport, not a production protocol encoding."""
    return ''.join(struct.pack('<9QBB',*row,*observation(row)).hex()+'\n' for row in cases()).encode()

if __name__ == '__main__':
    # Explicit regeneration keeps a deterministic checked-in independent fixture.
    (Path(__file__).parent/'fixtures/account-deposit-corpus.txt').write_bytes(encoded())
