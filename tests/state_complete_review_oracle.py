# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent arbitrary-precision complete review observations on independently rooted authored sources."""
from pathlib import Path
import struct
from state_complete_serialization_oracle import source
MAX = (1 << 64)-1
RATES = ((100, 2, 3), (0, 0, 0), (0, MAX, 0), (MAX, 1, 1))

def fields(service):
    """Read literal current metadata offsets without using native codecs or expected observations."""
    sid, raw, *_ = service
    number = lambda start, size: int.from_bytes(raw[start:start+size], 'little')
    return dict(id=sid, nominee=number(33,4), expected=number(37,4), liquid=number(41,8),
                protected=number(49,8), octets=number(73,8), gratis=number(81,8),
                items=number(89,4), created=number(93,4))

def observations(services, rates):
    """Exact nonnegative integer arithmetic and direct dictionary lookup produce independent expected rows."""
    rows = [fields(service) for service in services]
    directory = {row['id']: row['created'] for row in rows}
    base, item, octet = rates
    output = []
    for ordinal, row in enumerate(rows):
        minimum = max(0, base+item*row['items']+octet*row['octets']-row['gratis'])
        if minimum > MAX:
            return False, ordinal, row['id'], [] # No successful report prefix accompanies overflow.
        nominee = row['nominee']
        decision = 1 if nominee not in directory else (0 if directory[nominee] == row['expected'] else 2)
        effective = nominee if decision == 0 else row['id']
        output.extend((row['id'], minimum, int(row['liquid']+row['protected'] >= minimum), effective, decision))
    return True, 0, 0, output

def records():
    """Single and four-service sources use original and reverse declared order to expose late overflow ordinals."""
    for mode in range(3):
        for index in range(32 if mode == 0 else 8):
            services = [source(index)[1]] if mode == 0 else [source(4*index+i)[1] for i in range(4)]
            if mode == 2:
                services.reverse() # Reversal preserves the map while changing report traversal and failure order.
            for rates in RATES:
                ok, ordinal, sid, output = observations(services, rates)
                yield (mode, index, *rates, len(services), int(ok), ordinal, sid, *output)

def encoded():
    """Fixed E8 test words carry explicit inputs and observations outside production wire schemas."""
    return ''.join(struct.pack('<'+'Q'*len(row), *row).hex()+'\n' for row in records()).encode()

if __name__ == '__main__':
    # Explicit regeneration authors only the independently calculated fixture.
    (Path(__file__).parent/'fixtures/complete-review.txt').write_bytes(encoded())
