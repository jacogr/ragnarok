# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Drive actual fuzz-v1 sockets with independently calculated guest, fork, seed and checkpoint maps."""
import hashlib
import struct
import current_stf_report_guests_oracle as guests
import jam_fuzzer_guest_forks_oracle as forks
import jam_fuzzer_seed_guests_oracle as seeds
import jam_fuzzer_checkpoint_guests_oracle as checkpoints
from current_stf_oracle import decode_checkpoint
from current_stf_trace_genesis_oracle import initial_header
from jam_fuzzer_guest_reference import host_parameters
from native_fixture_contracts import FIXTURE_CONTRACTS
from state_layout_oracle import digest
from state_trace_wire_oracle import wire


def prepare_sessions(parameters):
    """Freeze every request and complete expected map before launching the target; no native output calculates inputs."""
    assert parameters == host_parameters(), 'Guest socket cases require their explicit zero-deposit512-byte profile'
    jobs, evidence = [], []
    for reference, identity in ((guests, 'current_stf_report_guests'), (forks, 'jam_fuzzer_guest_forks'),
                                (seeds, 'jam_fuzzer_seed_guests'), (checkpoints, 'jam_fuzzer_checkpoint_guests')):
        for path, expected in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == expected
        _, lines, calculated = reference.expected_observations()
        evidence.append(dict(reference=identity, fixture_sha256=hashlib.sha256(reference.FIXTURE.read_bytes()).hexdigest(),
                             expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest()))
        header, ancestors, pending = initial_header(), [], None
        for line in lines:
            tag, data = line.split(' ', 1)
            if tag == 'H':
                fields = data.split()
                assert len(fields) in (1, 2) and pending is None
                header = bytes.fromhex(fields[0])
                ancestors = [] if len(fields) == 1 else [(int(fields[1]), header[:32])]
            elif tag == 'P':
                assert pending is None
                state = wire(sorted(decode_checkpoint(bytes.fromhex(data)).items()))
                assert len(ancestors) <= 1
                membership = b''.join(slot.to_bytes(4, 'little')+identity for slot, identity in ancestors)
                jobs.append(dict(initialize=b'\x01'+header+state[32:]+bytes([len(ancestors)])+membership,
                                 header=header, state=state, steps=[]))
                header, ancestors = initial_header(), [] # A later seed uses only its own explicit header/evidence.
            elif tag in ('B', 'V'):
                assert jobs and pending is None
                pending = dict(kind=tag, block=bytes.fromhex(data))
            else:
                assert tag == 'O' and pending is not None
                pending['state'] = wire(sorted(decode_checkpoint(bytes.fromhex(data)).items()))
                jobs[-1]['steps'].append(pending)
                pending = None
        assert pending is None and all(job['steps'] for job in jobs)
    return jobs, dict(references=evidence, sessions=len(jobs),
                     signed_imports=sum(len(job['steps']) for job in jobs),
                     guest_siblings=sum(step['kind'] == 'V' for job in jobs for step in job['steps']))


def exercise_sessions(endpoint, jobs, evidence):
    """Use real negotiated sessions; compare exact whole-map frames and atomic rejection before every genuine guest import."""
    from nimony_fuzz import connect, exchange
    queries = rejections = siblings = 0
    for job in jobs:
        with connect(endpoint, features=3) as peer:
            assert exchange(peer, job['initialize']) == b'\x02'+job['state'][:32]
            selected_header, selected_state = job['header'], job['state']
            assert exchange(peer, b'\x04'+digest(selected_header)) == b'\x05'+selected_state[32:]
            queries += 1
            sibling = None
            for step in job['steps']:
                bad = bytearray(step['block'])
                bad[32] ^= 1
                assert exchange(peer, b'\x03'+bad)[0] == 255
                assert exchange(peer, b'\x04'+digest(selected_header)) == b'\x05'+selected_state[32:]
                rejections += 1
                queries += 1
                assert exchange(peer, b'\x03'+step['block']) == b'\x02'+step['state'][:32]
                selected_header, selected_state = step['block'][:297], step['state']
                assert exchange(peer, b'\x04'+digest(selected_header)) == b'\x05'+selected_state[32:]
                queries += 1
                if step['kind'] == 'V':
                    sibling = selected_header, selected_state # Keep the independent variant answer across original-last publication.
                elif sibling is not None:
                    assert exchange(peer, b'\x04'+digest(sibling[0])) == b'\x05'+sibling[1][32:]
                    queries += 1
                    siblings += 1
                    sibling = None
            assert exchange(peer, b'\x04'+digest(job['header'])) == b'\x05'+job['state'][32:]
            queries += 1
    with connect(endpoint, features=3) as peer:
        # A reconnect contains only its explicit seed; previous nonempty guest execution cannot leak into it.
        assert exchange(peer, jobs[-1]['initialize']) == b'\x02'+jobs[-1]['state'][:32]
        payload = b'\x04'+digest(jobs[-1]['steps'][-1]['block'][:297])
        peer.sendall(struct.pack('<I', len(payload))+payload)
        assert peer.recv(1) == b''
    assert siblings == evidence['guest_siblings']
    return dict(passed=True, **evidence, complete_state_queries=queries,
                consensus_rejections=rejections, isolated_reconnects=1,
                scope='fixed independently calculated whole-map guest socket cases; no generated campaign')
