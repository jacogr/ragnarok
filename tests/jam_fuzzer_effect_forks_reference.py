# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent same-quorum guest siblings preserve operands/effects while changing signed assurance and history facts."""
import hashlib
import importlib
import json
from current_stf_oracle import Reader, decode_checkpoint, checkpoint, history, tree, sign
from current_stf_reporting_oracle import assurances
from report_oracle import decode as report_decode
from state_history_oracle import wire as history_wire
from state_layout_oracle import chapter_key, digest
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire, DEFAULT
from test_codec import reference_encode as natural
from header_oracle import decode as header_parse, TINY
from jam_fuzzer_guest_reference import host_parameters


def assurance_bytes(rows):
    """Serialize exact independent parent/bit/index/signature tuples under the fixed two-core profile."""
    return natural(len(rows))+b''.join(row['anchor']+bytes([row['bits']])+row['index'].to_bytes(2, 'little')+row['signature'] for row in rows)


def body_parts(raw):
    """Parse only the declared current empty-ticket/dispute profile; preserve exact preimage and guarantee projections."""
    reader = Reader(raw)
    assert reader.count() == 0 # These authored guest families have no tickets; unknown profiles cannot silently adapt.
    supplied = []
    for _ in range(reader.count()):
        service = reader.take(4)
        value = reader.take(reader.count())
        supplied.append(service+digest(value))
    guarantees = []
    for _ in range(reader.count()):
        decoded = report_decode(raw[reader.at:], 2)
        assert isinstance(decoded, str) and decoded.split()[-1].isdigit(), 'Invalid independently framed report'
        report = reader.take(int(decoded.split()[-1]))
        slot = reader.take(4)
        count = reader.count()
        credentials = reader.take(66*count)
        guarantees.append(digest(report)+slot+natural(count)+credentials)
    offset = reader.at
    count = reader.count()
    assert count <= 6
    rows = []
    for _ in range(count):
        rows.append(dict(anchor=reader.take(32), bits=reader.take(1)[0],
                         index=int.from_bytes(reader.take(2), 'little'), signature=reader.take(64)))
    assert reader.take(3) == bytes(3)
    reader.done()
    return offset, rows, natural(len(supplied))+b''.join(supplied), natural(len(guarantees))+b''.join(guarantees)


def sibling(parent, original, posterior):
    """Add the sixth assurance without changing availability, guest operands, execution order or entropy; derive C3/C13 anew."""
    assert original[100:104] == bytes(4) and original[200] == 0
    slot = int.from_bytes(original[96:100], 'little')
    assert slot//12 == int.from_bytes(parent[chapter_key(11)], 'little')//12
    offset, old, supplied, guaranteed = body_parts(original[297:])
    assert len(old) == 5 and all(row['bits'] == old[0]['bits'] for row in old)
    assert old[0]['bits'] in (1, 2, 3)
    expected = assurances(parent, 5, old[0]['bits'])
    assert old == expected # The original independently signed quorum is checked before constructing another valid one.
    changed = assurances(parent, 6, old[0]['bits'])
    before = assurance_bytes(old)
    after = assurance_bytes(changed)
    root = digest(digest(b'\0')+digest(supplied)+digest(guaranteed)+digest(before)+digest(bytes(3)))
    assert root == original[64:96]
    commitment = digest(digest(b'\0')+digest(supplied)+digest(guaranteed)+digest(after)+digest(bytes(3)))
    context = b'jam_fallback_seal'+parent[chapter_key(6)][96:128]
    assert sign(1, context, original[:201])[0] == original[201:297]
    unsigned = original[:64]+commitment+original[96:201]
    seal, _ = sign(1, context, unsigned)
    raw = original[297:297+offset]+after+bytes(3)
    block = unsigned+seal+raw
    result = dict(posterior) # This is an independent frozen mathematical successor, never an observed native state.
    records, peaks = history(result[chapter_key(3)])
    fixed, packages = records[-1]
    assert fixed[:32] == digest(original[:297])
    records[-1] = (digest(block[:297])+fixed[32:], packages)
    result[chapter_key(3)] = history_wire((records, peaks))
    (current, previous, cores, services), _ = statistics_parse(result[chapter_key(13)], DEFAULT)
    current = list(current)
    row = list(current[5]); row[5] += 1; current[5] = tuple(row)
    cores = [list(row) for row in cores]
    for core in range(2):
        if old[0]['bits'] & (1 << core):
            cores[core][1] += 1 # The additional valid signer changes votes, not the already-qualified report set.
    result[chapter_key(13)] = statistics_wire((current, previous, cores, services))
    assert {key for key in result if result[key] != posterior[key]} == {chapter_key(3), chapter_key(13)}
    return block, result


def group(families, fixture, *, check_frozen=True):
    """Freeze complete same-parent siblings across coherent effect families, continuing only their original-last successors."""
    lines, roots, bases = [], [], {}
    transitions = chains = variants = 0
    for family in families:
        module = importlib.import_module('current_stf_'+family+'_oracle')
        _, source, _ = module.expected_observations()
        bases[family] = hashlib.sha256(module.FIXTURE.read_bytes()).hexdigest()
        parent = None
        changed = False
        wire = None
        for line in source:
            tag, data = line.split(' ', 1)
            if tag == 'P':
                assert parent is None or changed
                parent = decode_checkpoint(bytes.fromhex(data))
                changed = False
                chains += 1
                lines.append(line)
            elif tag == 'B':
                assert wire is None
                wire = bytes.fromhex(data)
            else:
                assert tag == 'O' and wire is not None
                posterior = decode_checkpoint(bytes.fromhex(data))
                parsed = header_parse('H', wire, TINY)
                assert parsed.split()[0].isdigit(), 'Invalid independently framed header'
                extent = int(parsed.split()[0])
                _, votes, _, _ = body_parts(wire[extent:])
                if not changed and extent == 297 and len(votes) == 5 and votes[0]['bits'] != 0:
                    variant, state = sibling(parent, wire, posterior)
                    lines.extend(('V '+variant.hex(), 'O '+checkpoint(list(state.items())).hex()))
                    roots.append(tree(list(state.items()))[0].hex())
                    variants += 1
                    transitions += 1
                    changed = True
                lines.extend(('B '+wire.hex(), line))
                transitions += 1
                parent = posterior
                wire = None
        assert changed and wire is None
    evidence = dict(graypaper_commit='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d',
                    families=list(families), bases=bases, transitions=transitions, chains=chains,
                    sibling_imports=variants, sibling_roots=roots,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    assert variants == chains
    if check_frozen:
        assert json.loads(fixture.read_text()) == evidence
    return [], lines, evidence


def profiles(families):
    """Retain each frozen source's explicit deposits/code-size controls; never infer a profile from an observed root."""
    result = []
    for family in families:
        module = importlib.import_module('current_stf_'+family+'_oracle')
        frozen = json.loads(module.FIXTURE.read_text())
        roots = frozen['successor_roots']
        assert roots and all(isinstance(chain, list) and chain for chain in roots)
        count = len(roots) # Frozen source chains declare profile cardinality; group() separately checks every mathematical successor.
        sizes = frozen.get('max_service_code_sizes', [frozen.get('max_service_code_size', 512)]*count)
        assert len(sizes) == count
        deposits = frozen.get('deposits', dict(per_item=0, per_byte=0, per_account=0))
        result.extend(host_parameters(code_limit=size, deposits=tuple(deposits[key] for key in ('per_item', 'per_byte', 'per_account'))) for size in sizes)
    return result
