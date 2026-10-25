# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Actual eight-state fork eviction and later retirement use only independently prepared whole-map traces."""
import struct
from state_layout_oracle import digest


def bind(job):
    """Bind two required local-EOF observations to the frozen nine-variant/eight-position source plan."""
    assert job['fork_capacity'] == 8
    assert [step['kind'] for step in job['steps']] == ['V']*9+['B','B']
    job['fork_retention'] = dict(initialize=job['initialize'],header=job['header'],state=job['state'],steps=tuple(job['steps']))


def exercise(endpoint,plan):
    """Compare retained complete maps, then require local unknown-state closure for evicted and retired identities."""
    from nimony_fuzz import connect,exchange
    # Eviction follows nine siblings; retirement follows original-last plus its next direct extension.
    for retired in (False,True):
        with connect(endpoint,features=3) as peer:
            assert exchange(peer,plan['initialize']) == b'\x02'+plan['state'][:32]
            assert exchange(peer,b'\x04'+digest(plan['header'])) == b'\x05'+plan['state'][32:]
            for step in plan['steps'][:11 if retired else 9]:
                assert exchange(peer,b'\x03'+step['block']) == b'\x02'+step['state'][:32]
                assert exchange(peer,b'\x04'+digest(step['header'])) == b'\x05'+step['state'][32:]
            if not retired:
                # All eight most recent variant maps remain exact when the first one is evicted.
                for step in plan['steps'][1:9]:
                    assert exchange(peer,b'\x04'+digest(step['header'])) == b'\x05'+step['state'][32:]
            selected = plan['steps'][8 if retired else 0]
            payload = b'\x04'+digest(selected['header'])
            peer.sendall(struct.pack('<I',len(payload))+payload)
            assert peer.recv(1) == b'' # Unknown local retention is not a fabricated consensus Error.
    return 2
