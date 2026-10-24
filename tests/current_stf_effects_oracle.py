# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map preimage, storage, yield and checkpoint STF cases.

Only the literal authored guests are modeled: register immediates, one write/yield and optional
checkpoint followed by halt/trap. Gas comes from the independent pinned-table pipeline simulator
plus the literal GP host prices, never observed native gas or a stored successor map.
"""
from functools import lru_cache
import hashlib
import json
from pathlib import Path
from current_stf_oracle import (decode_checkpoint, authored_child, advance_no_reports,
                                checkpoint, tree)
from state_layout_oracle import chapter_key, chapter_service, digest
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire
from state_accounts_oracle import parse as metadata_parse, wire as metadata_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire, DEFAULT
from pvm_gas_reference import blob, simulate, tables
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/current-stf-effects.json'
MODES = ('create', 'replace', 'delete', 'panic-rollback', 'checkpoint-panic')
PAYLOADS = ((42, b'I'), (99, b'Q'))
COMMITMENT = bytes(range(32))


def immediate(register, value):
    """Literal load_imm_64 octets set all eight bits of each public fixture byte."""
    return bytes([20, register])+value.to_bytes(8, 'little')


def envelope(instructions, memory):
    """Independently encode the fixed entry-five guest, opcode mask and initialized RAM."""
    raw = blob(instructions, prefix=[b'\0']*5)
    header = b'\1\0\0'+len(memory).to_bytes(3, 'little')+b'\1\0\1\0\0I'
    return b'\0'+header+memory+len(raw).to_bytes(4, 'little')+raw


def guest(mode):
    """Explicit guest inputs determine both state mutations and terminal implication selection."""
    assert mode in MODES
    value = b'' if mode == 'delete' else bytes([9, 8, 7])
    memory = (b'\7'+value).ljust(32, b'\0')+COMMITMENT
    instructions = [immediate(7, 2**64-1), immediate(8, 196608), immediate(9, 1),
                    immediate(10, 196609), immediate(11, len(value)), bytes([10, 5]),
                    immediate(7, 196640), bytes([10, 27])]
    if mode == 'checkpoint-panic':
        instructions.append(bytes([10, 19]))
    instructions.append(b'\0' if mode in ('panic-rollback', 'checkpoint-panic') else bytes([50, 0]))
    return instructions, memory, value


@lru_cache(maxsize=1)
def gas_definitions():
    """Parse the unchanged pinned GP table once for all independently calculated guest charges."""
    return tables()


def guest_gas(mode):
    """Charge one basic block, the rounded write cost, yield and optional checkpoint."""
    instructions, _, value = guest(mode)
    block, _ = simulate(instructions, gas_definitions(), prefix=[b'\0']*5)
    write = 2442+(3358+1023)//1024+(216*len(value)+1023)//1024
    return block+write+98+(103 if mode == 'checkpoint-panic' else 0)


def preimage_body(payloads):
    """Encode only requested preimages; tickets, guarantees, assurances and disputes stay empty."""
    assert list(payloads) == sorted(set(payloads)), 'ordered unique preimage pairs required'
    values = natural(len(payloads))+b''.join(sid.to_bytes(4, 'little')+natural(len(value))+value
                                             for sid, value in payloads)
    projected = natural(len(payloads))+b''.join(sid.to_bytes(4, 'little')+digest(value)
                                                for sid, value in payloads)
    parts = [b'\0', projected, b'\0', b'\0', bytes(3)]
    return b'\0'+values+bytes(5), digest(b''.join(map(digest, parts)))


def validate_parent(parent, mode):
    """Bind expected effects to actual original literal code, funding, privileges and solicitations."""
    instructions, memory, _ = guest(mode)
    codes = [envelope([bytes([50, 0])], b'Q'), envelope(instructions, memory)]
    for sid, code in zip((42, 99), codes):
        metadata = metadata_parse(parent[chapter_service(255, sid)], 105)
        assert not isinstance(metadata, str) and metadata[0] == digest(code)
        assert parent[value_key('P', sid, digest(code))] == code
        if sid == 99:
            assert metadata[1][0] == 1_000_000 # Only this service performs a funded storage mutation.
        assert parent[request_key(sid, digest(code), len(code))] == request_wire((1,))
    for sid, value in PAYLOADS:
        assert parent[request_key(sid, digest(value), len(value))] == b'\0'
        assert value_key('P', sid, digest(value)) not in parent
    # Exact same always-accumulate allowance pairs drive the two real guest invocations.
    privileges = parent[chapter_key(12)]
    assert privileges[-25:] == (b'\2'+b''.join(sid.to_bytes(4, 'little')
                                            +(100000).to_bytes(8, 'little') for sid in (42, 99)))


def successor(parent, mode, payloads):
    """Calculate a signed child and all successor entries before consulting any native output."""
    body, commitment = preimage_body(payloads)
    for sid, value in payloads:
        assert parent.get(request_key(sid, digest(value), len(value))) == b'\0', 'preimage not requested'
    child = authored_child(parent, body, commitment)
    slot = int.from_bytes(child[96:100], 'little')
    retained = mode != 'panic-rollback'
    outputs = ((99, COMMITMENT),) if retained else ()
    result = advance_no_reports(parent, child, body, commitment, outputs=outputs, preimages=payloads)
    # Explicit code semantics select X on halt, Y on panic; checkpoint assigns the actual X to Y.
    _, _, value = guest(mode)
    if retained:
        key = value_key('S', 99, b'\7')
        previous = parent.get(key)
        metadata = metadata_parse(parent[chapter_service(255, 99)], 105)
        code, wide, narrow = metadata[0], list(metadata[1]), list(metadata[2])
        if previous is not None:
            narrow[0] -= 1
            wide[4] -= 34+1+len(previous)
        if value:
            narrow[0] += 1
            wide[4] += 34+1+len(value)
            result[key] = value
        else:
            result.pop(key, None)
        assert narrow[0] >= 0 and wide[4] >= 0
        result[chapter_service(255, 99)] = metadata_wire((code, wide, narrow))
    # Both positive-gas S keys get current last-accumulation time, including the panicking service.
    halt_gas = simulate([bytes([50, 0])], gas_definitions(), prefix=[b'\0']*5)[0]
    charges = (halt_gas, guest_gas(mode))
    parsed = statistics_parse(result[chapter_key(13)], DEFAULT)
    assert not isinstance(parsed, str)
    (current, previous, cores, _), _ = parsed
    services = []
    for sid, gas in zip((42, 99), charges):
        code, wide, narrow = metadata_parse(result[chapter_service(255, sid)], 105)
        narrow = list(narrow)
        narrow[2] = slot
        result[chapter_service(255, sid)] = metadata_wire((code, wide, narrow))
        values = [value for service, value in payloads if service == sid]
        services.append((sid, len(values), sum(map(len, values)), 0, 0, 0, 0, 0, 0, 0, 0, gas))
    result[chapter_key(13)] = statistics_wire((current, previous, cores, services))
    # Fulfillment occurs after accumulation and preserves existing metadata/footprint reservations.
    for sid, value in payloads:
        key = request_key(sid, digest(value), len(value))
        assert parent[key] == b'\0' and result[key] == b'\0'
        result[key] = request_wire((slot,))
        result[value_key('P', sid, digest(value))] = value
    return child, result


def expected_observations():
    """Return every original input, independent signed child and complete golden output before native execution."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    assert [case['mode'] for case in fixture['cases']] == list(MODES)
    lines, roots, inputs = [], [], []
    for case in fixture['cases']:
        original = bytes.fromhex(case['parent_checkpoint'])
        parent = decode_checkpoint(original)
        validate_parent(parent, case['mode'])
        lines.append('P '+original.hex())
        inputs.append(hashlib.sha256(original).hexdigest())
        case_roots = []
        assert len(case['successor_roots']) == len(case['successor_checkpoint_sha256']) == 2
        for index, payloads in enumerate((PAYLOADS, ())):
            child, parent = successor(parent, case['mode'], payloads)
            encoded = checkpoint(list(parent.items()))
            root = tree(list(parent.items()))[0].hex()
            assert root == case['successor_roots'][index]
            assert hashlib.sha256(encoded).hexdigest() == case['successor_checkpoint_sha256'][index]
            case_roots.append(root)
            inputs.append(hashlib.sha256(child).hexdigest())
            lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
        roots.append(case_roots)
    evidence = dict(transitions=10, nonempty_extrinsics=5, guest_executions=20, roots=roots,
                    inputs_sha256=inputs, guest_gas={mode: guest_gas(mode) for mode in MODES})
    return lines, evidence
