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


def reference_sessions(reference, identity, parameters=None, *, spec='tiny'):
    """Freeze exact independent headers/maps under one explicitly declared host profile per source chain."""
    from header_oracle import decode as decode_header, TINY, FULL
    assert spec in ('tiny', 'full')
    geometry = TINY if spec == 'tiny' else FULL
    for path, expected in FIXTURE_CONTRACTS[identity][2]:
        assert hashlib.sha256(path.read_bytes()).hexdigest() == expected
    _, lines, _ = reference.expected_observations()
    count = sum(line.startswith('P ') for line in lines)
    parameters = [host_parameters()]*count if parameters is None else parameters
    assert len(parameters) == count and all(isinstance(value, bytes) and len(value) == 122 for value in parameters)
    profiles = iter(parameters)
    jobs = []
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
                             header=header, state=state, steps=[], parameters=next(profiles), spec=spec))
            header, ancestors = initial_header(), [] # Later seeds retain only their own explicit header/evidence.
        elif tag in ('B', 'V'):
            assert jobs and pending is None
            block = bytes.fromhex(data)
            parsed = decode_header('H', block, geometry)
            assert parsed.split()[0].isdigit(), 'Invalid independently framed guest header'
            extent = int(parsed.split()[0])
            pending = dict(kind=tag, block=block, header=block[:extent])
        else:
            assert tag == 'O' and pending is not None
            pending['state'] = wire(sorted(decode_checkpoint(bytes.fromhex(data)).items()))
            jobs[-1]['steps'].append(pending)
            pending = None
    assert pending is None and all(job['steps'] for job in jobs)
    evidence = dict(reference=identity, fixture_sha256=hashlib.sha256(reference.FIXTURE.read_bytes()).hexdigest(),
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    return jobs, evidence


def session_evidence(jobs, references):
    """Declare complete workload counts before startup; later observations must match each planned exchange."""
    return dict(references=references, sessions=len(jobs),
                signed_imports=sum(len(job['steps']) for job in jobs),
                guest_siblings=sum(step['kind'] == 'V' for job in jobs for step in job['steps']),
                expected_state_queries=sum(2+2*len(job['steps'])+sum(step['kind'] == 'V' for step in job['steps']) for job in jobs))


def prepare_sessions(parameters):
    """Preserve the original explicit zero-deposit512-byte workload for its existing socket consumers."""
    assert parameters == host_parameters(), 'Guest socket cases require their explicit zero-deposit512-byte profile'
    jobs, evidence = [], []
    for reference, identity in ((guests, 'current_stf_report_guests'), (forks, 'jam_fuzzer_guest_forks'),
                                (seeds, 'jam_fuzzer_seed_guests'), (checkpoints, 'jam_fuzzer_checkpoint_guests')):
        selected, proof = reference_sessions(reference, identity)
        jobs.extend(selected); evidence.append(proof)
    return jobs, session_evidence(jobs, evidence)


def prepare_effect_sessions():
    """Add every coherent complex-effect sibling family with its original explicit deposit/code profiles."""
    import importlib
    from jam_fuzzer_effect_forks_reference import profiles
    jobs, initial = prepare_sessions(host_parameters())
    evidence = list(initial['references'])
    for name in ('transfer', 'account', 'privileged', 'supervised', 'deferred'):
        identity = 'jam_fuzzer_'+name+'_forks'
        reference = importlib.import_module(identity+'_oracle')
        selected, proof = reference_sessions(reference, identity, profiles(reference.FAMILIES))
        jobs.extend(selected); evidence.append(proof)
    import jam_fuzzer_epoch_effect_forks_oracle as epoch
    selected, proof = reference_sessions(epoch, 'jam_fuzzer_epoch_effect_forks', epoch.host_profiles())
    jobs.extend(selected); evidence.append(proof)
    import jam_fuzzer_full_profile_oracle as full
    selected, proof = reference_sessions(full, 'jam_fuzzer_full_profile', [full.parameters()]*2, spec='full')
    jobs.extend(selected); evidence.append(proof)
    import jam_fuzzer_full_guests_oracle as full_guests
    selected, proof = reference_sessions(full_guests, 'jam_fuzzer_full_guests', [full.parameters()]*len(full_guests.MODES), spec='full')
    jobs.extend(selected); evidence.append(proof)
    return jobs, session_evidence(jobs, evidence)


def exercise_sessions(endpoint, jobs, evidence):
    """Use real negotiated sessions; compare exact whole-map frames and atomic rejection before every genuine guest import."""
    from nimony_fuzz import connect, exchange
    queries = rejections = siblings = completed_imports = completed_sessions = 0
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
                completed_imports += 1
                selected_header, selected_state = step['header'], step['state']
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
            completed_sessions += 1
    with connect(endpoint, features=3) as peer:
        # A reconnect contains only its explicit seed; previous nonempty guest execution cannot leak into it.
        assert exchange(peer, jobs[-1]['initialize']) == b'\x02'+jobs[-1]['state'][:32]
        payload = b'\x04'+digest(jobs[-1]['steps'][-1]['header'])
        peer.sendall(struct.pack('<I', len(payload))+payload)
        assert peer.recv(1) == b''
    assert siblings == evidence['guest_siblings']
    assert completed_imports == evidence['signed_imports'] and completed_sessions == evidence['sessions']
    assert queries == evidence['expected_state_queries']
    return dict(passed=True, **evidence, complete_state_queries=queries,
                completed_imports=completed_imports, completed_sessions=completed_sessions, retained_siblings=siblings,
                consensus_rejections=rejections, isolated_reconnects=1,
                scope='fixed independently calculated whole-map guest socket cases; no generated campaign')
