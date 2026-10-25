# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Known framed-stream interruptions after independently calculated full guest state, with atomic recovery."""
import hashlib
import json
from pathlib import Path
import socket
import struct
from state_layout_oracle import digest

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-stream-recovery.json'


def bind(job, check_frozen=True):
    """Declare exact interruption bytes and whole-map operands before the actual target is started."""
    assert job['spec'] == 'full' and len(job['steps']) >= 3
    prefix = job['steps'][:2]; following = job['steps'][2]
    assert all(step['kind'] == 'B' for step in (*prefix,following))
    assert [int.from_bytes(step['block'][96:100],'little') for step in (*prefix,following)] == [5,6,7]
    payload = b'\x03'+following['block']; framed = struct.pack('<I',len(payload))+payload
    cases = []
    # Partial E4 prefixes and structured body cutpoints end with an explicit write-half close.
    for count in range(4): cases.append(('prefix-'+str(count),framed[:count]))
    for count in (0,1,33,97,297,len(payload)-1): cases.append(('body-'+str(count),framed[:4+count]))
    # Complete invalid frames exercise distinct frame and message-decoder refusals without allocation-sized payloads.
    cases.extend((('empty-frame',bytes(4)),('oversized-frame',(16777217).to_bytes(4,'little')),
                  ('unknown-tag',b'\1\0\0\0\xfe'),('truncated-import',b'\1\0\0\0\3')))
    bad = bytearray(following['block']);bad[32] ^= 1
    evidence = dict(cases=[dict(name=name,bytes=len(data),sha256=hashlib.sha256(data).hexdigest()) for name,data in cases],
                    control_count=len(cases)+1, initialize_sha256=hashlib.sha256(job['initialize']).hexdigest(),
                    prefix_state_sha256=[hashlib.sha256(step['state']).hexdigest() for step in prefix],
                    continuation_state_sha256=hashlib.sha256(following['state']).hexdigest(),
                    bad_prior_root_sha256=hashlib.sha256(bad).hexdigest())
    # Frozen packet identities and independent full-state hashes define every required recovery before execution.
    if check_frozen:
        from native_fixture_contracts import FIXTURE_CONTRACTS
        for path,expected in FIXTURE_CONTRACTS['jam_fuzzer_stream_recovery'][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == expected
        assert json.loads(FIXTURE.read_text()) == evidence
    job['stream_recovery'] = dict(initialize=job['initialize'],header=job['header'],state=job['state'],
                                  prefix=tuple(prefix),following=following,cases=tuple(cases),bad=bytes(bad))
    return evidence


def prime(endpoint, plan):
    """Own one negotiated socket and establish exact independently calculated seed/report/guest maps."""
    from nimony_fuzz import connect, exchange
    peer = connect(endpoint,features=3)
    try:
        assert exchange(peer,plan['initialize']) == b'\x02'+plan['state'][:32]
        assert exchange(peer,b'\x04'+digest(plan['header'])) == b'\x05'+plan['state'][32:]
        for step in plan['prefix']:
            assert exchange(peer,b'\x03'+step['block']) == b'\x02'+step['state'][:32]
            assert exchange(peer,b'\x04'+digest(step['header'])) == b'\x05'+step['state'][32:]
        return peer
    except BaseException:
        peer.close() # Failed setup never leaves a live unowned client behind.
        raise


def exercise(endpoint, plan):
    """Require immediate local EOF, fresh-session isolation and atomic GP refusal before valid continuation."""
    from nimony_fuzz import connect, exchange
    completed = 0; current = plan['prefix'][-1]
    # Each interruption occurs only after nonempty guest execution and full-state equality in its own connection.
    for name,data in plan['cases']:
        with prime(endpoint,plan) as peer:
            peer.sendall(data);peer.shutdown(socket.SHUT_WR)
            assert peer.recv(1) == b'', name
        with connect(endpoint,features=3) as peer:
            assert exchange(peer,plan['initialize']) == b'\x02'+plan['state'][:32]
            payload = b'\x04'+digest(current['header'])
            peer.sendall(struct.pack('<I',len(payload))+payload)
            assert peer.recv(1) == b'', name+' retained another connection state'
        completed += 1
    # A complete GP-invalid block returns consensus Error and leaves the entire guest map unchanged.
    with prime(endpoint,plan) as peer:
        assert exchange(peer,b'\x03'+plan['bad'])[0] == 255
        assert exchange(peer,b'\x04'+digest(current['header'])) == b'\x05'+current['state'][32:]
        following = plan['following']
        assert exchange(peer,b'\x03'+following['block']) == b'\x02'+following['state'][:32]
        assert exchange(peer,b'\x04'+digest(following['header'])) == b'\x05'+following['state'][32:]
    return completed+1
