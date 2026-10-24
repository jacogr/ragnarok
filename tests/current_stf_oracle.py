# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map STF reference for authored same-epoch empty-body blocks.

GP 1fa8cbc authorization, recent_history, safrole, statistics and accumulation equations.
This bounded test reference uses mathematical Thin signing and independent trie/Keccak equations;
it neither invokes the native backend nor consumes an observed successor to calculate an answer.
No guest execution, epoch change, ticket admission or full published trace parity is claimed here.
"""
import hashlib
import json
from pathlib import Path
from bandersnatch_thin_oracle import sign
from state_complete_serialization_oracle import MAGIC, checkpoint
from state_layout_oracle import chapter_key, chapter_service, digest
from state_statistics_oracle import parse as parse_statistics, wire as statistics_wire, DEFAULT
from state_history_oracle import wire as history_wire
from state_trie_oracle import tree
from test_codec import reference_decode, reference_encode as natural
from test_crypto import keccak256
from history_transition_fixtures import output_root

FIXTURE = Path(__file__).parent/'fixtures/current-stf.json'


class Reader:
    """Trusted independent framing still requires complete canonical fields and final consumption."""

    def __init__(self, data):
        """Own a public fixture byte string and a private decoding position."""
        self.data, self.at = data, 0

    def take(self, size):
        """Refuse truncation rather than silently shortening a fixed field."""
        assert 0 <= size <= len(self.data)-self.at
        result = self.data[self.at:self.at+size]
        self.at += size
        return result

    def count(self):
        """Use the independent canonical JAM natural reference, never a native codec."""
        parsed = reference_decode(self.data[self.at:])
        assert parsed not in ('truncated', 'noncanonical'), parsed
        value, size = map(int, parsed.split())
        self.take(size)
        return value

    def done(self):
        """Trailing bytes are not part of a complete chapter or checkpoint."""
        assert self.at == len(self.data)


def decode_checkpoint(data):
    """Recompute the complete root and require exact order, extent and envelope bytes."""
    source = Reader(data)
    assert source.take(len(MAGIC)) == MAGIC
    count = int.from_bytes(source.take(8), 'little')
    committed = source.take(32)
    rows = [(source.take(31), source.take(int.from_bytes(source.take(8), 'little')))
            for _ in range(count)]
    source.done()
    assert [key for key, _ in rows] == sorted(set(key for key, _ in rows))
    assert tree(rows)[0] == committed
    assert checkpoint(rows) == data
    return dict(rows)


def history(data):
    """Separate fixed tuples, canonical package dictionaries and optional MMR belt peaks."""
    source = Reader(data)
    blocks = [(source.take(100), source.take(64*source.count()))
              for _ in range(source.count())]
    peaks = []
    # Absence is an actual position, not an all-zero present peak.
    for _ in range(source.count()):
        tag = source.take(1)
        assert tag in (b'\0', b'\1')
        peaks.append(None if tag == b'\0' else source.take(32))
    source.done()
    assert history_wire((blocks, peaks)) == data
    return blocks, peaks


def authored_child(parent, body=bytes(7), extrinsic_root=None):
    """Independently sign a same-epoch child with explicitly calculated body commitment."""
    blocks, _ = history(parent[chapter_key(3)])
    entropy = parent[chapter_key(6)]
    slot = int.from_bytes(parent[chapter_key(11)], 'little')+1
    context = b'jam_fallback_seal'+entropy[96:128]
    _, output = sign(1, context, b'')
    proof, _ = sign(1, b'jam_entropy'+output, b'')
    if extrinsic_root is None:
        assert body == bytes(7)
        extrinsic_root = digest(4*digest(b'\0')+digest(bytes(3)))
    unsigned = (blocks[-1][0][:32]+tree(list(parent.items()))[0]
                +extrinsic_root+slot.to_bytes(4, 'little')
                +bytes(4)+proof+b'\0')
    seal, _ = sign(1, context, unsigned)
    return unsigned+seal+body


def expected_observations():
    """Freeze complete expected wires from two explicit original maps and independent equations."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    lines = []
    for case in fixture['cases']:
        original = bytes.fromhex(case['parent_checkpoint'])
        parent = decode_checkpoint(original)
        lines.append('P '+original.hex())
        assert len(case['successor_roots']) == len(case['successor_checkpoint_sha256']) == 10
        for root, sha in zip(case['successor_roots'], case['successor_checkpoint_sha256']):
            child = authored_child(parent)
            parent = successor(parent, child)
            encoded = checkpoint(list(parent.items()))
            assert tree(list(parent.items()))[0].hex() == root
            assert hashlib.sha256(encoded).hexdigest() == sha
            lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
    return lines


def advance_no_reports(parent, child, body, extrinsic_root, *, outputs=(), preimages=()):
    """Shared no-report equations accept explicit independent preimage/output observations."""
    assert len(child) == 297+len(body) and child[297:] == body
    assert child[100:104] == bytes(4) and child[200:201] == b'\0', 'no markers/offenders, author zero'
    slot = int.from_bytes(child[96:100], 'little')
    prior_slot = int.from_bytes(parent[chapter_key(11)], 'little')
    assert 1 <= prior_slot < slot < 12 and slot == prior_slot+1
    prior_root = tree(list(parent.items()))[0]
    assert child[32:64] == prior_root
    assert child[64:96] == extrinsic_root
    entropy = parent[chapter_key(6)]
    assert len(entropy) == 128
    context = b'jam_fallback_seal'+entropy[96:128]
    _, output = sign(1, context, b'')
    proof, fresh_output = sign(1, b'jam_entropy'+output, b'')
    assert child[104:200] == proof
    seal, _ = sign(1, context, child[:201])
    assert child[201:297] == seal
    return advance_chapters(parent, child[:297], slot, 0, fresh_output,
                            outputs=outputs, preimages=preimages)


def advance_chapters(parent, header, slot, author, entropy_output, *, outputs=(), preimages=(),
                     ticket_count=0, cores=2):
    """Advance no-report global chapters after a feature reference has independently authored its header."""
    prior_slot = int.from_bytes(parent[chapter_key(11)], 'little')
    assert slot > prior_slot and cores in (2, 3)
    crossed = slot//12 > prior_slot//12
    current_count = Reader(parent[chapter_key(8)]).count()
    previous_count = Reader(parent[chapter_key(9)]).count()
    active_count = Reader(parent[chapter_key(4)]).count() if crossed else current_count
    assert 6 <= active_count <= 3*cores and active_count % 3 == 0 and 0 <= author < active_count
    prior_root = tree(list(parent.items()))[0]
    assert header[32:64] == prior_root and int.from_bytes(header[96:100], 'little') == slot
    entropy = parent[chapter_key(6)]
    result = dict(parent)
    result[chapter_key(6)] = digest(entropy[:32]+entropy_output)+(entropy[:96] if crossed else entropy[32:])
    result[chapter_key(11)] = slot.to_bytes(4, 'little')
    # No guarantees remove pool entries; append the indexed queue hash and retain the newest eight.
    pools = Reader(parent[chapter_key(1)])
    queues = parent[chapter_key(2)]
    assert len(queues) == cores*80*32
    rows = []
    for core in range(cores):
        count = pools.count()
        assert count <= 8
        row = pools.take(32*count)
        offset = (core*80+slot % 80)*32
        row = (row+queues[offset:offset+32])[-256:]
        rows.append(natural(len(row)//32)+row)
    pools.done()
    result[chapter_key(1)] = b''.join(rows)
    # Recent history corrects the parent, appends the independently derived output root and bags peaks.
    blocks, peaks = history(parent[chapter_key(3)])
    assert blocks[-1][0][:32] == header[:32]
    fixed, pairs = blocks[-1]
    blocks[-1] = (fixed[:64]+prior_root+fixed[96:], pairs)
    leaves = [service.to_bytes(4, 'little')+commitment for service, commitment in outputs]
    result[chapter_key(16)] = natural(len(leaves))+b''.join(leaves)
    carry = output_root(leaves)
    position = 0
    while position < len(peaks) and peaks[position] is not None:
        carry = bytes.fromhex(keccak256(peaks[position]+carry))
        peaks[position] = None
        position += 1
    if position == len(peaks):
        peaks.append(carry)
    else:
        peaks[position] = carry
    present = [peak for peak in peaks if peak is not None]
    bag = present[0]
    for peak in present[1:]:
        bag = bytes.fromhex(keccak256(b'peak'+bag+peak))
    blocks.append((digest(header)+bag+bytes(32)+slot.to_bytes(4, 'little'), b''))
    result[chapter_key(3)] = history_wire((blocks[-8:], peaks))
    parsed = parse_statistics(parent[chapter_key(13)], (cores, current_count, previous_count, *DEFAULT[3:]))
    assert not isinstance(parsed, str), parsed
    (current, previous, _, _), consumed = parsed
    assert consumed == len(parent[chapter_key(13)])
    if crossed:
        previous, current = current, [(0,)*6]*active_count
    row = list(current[author])
    row[0] += 1
    row[1] += ticket_count
    row[2] += len(preimages)
    row[3] += sum(len(value) for _, value in preimages)
    current[author] = tuple(row)
    result[chapter_key(13)] = statistics_wire((current, previous, [(0,)*8]*cores, []))
    assert set(result) == set(parent)
    return result


def successor(parent, child):
    """Bound empty-body cases separately from the explicit guest-effect whole-map reference."""
    assert len(child) == 304 and child[297:] == bytes(7), 'bounded empty-body wire only'
    # No available reports, ready work, provisions or accumulation outputs can introduce effects.
    assert parent[chapter_key(10)] == bytes(2)
    assert parent[chapter_key(14)] == bytes(12)
    assert parent[chapter_key(15)] == bytes(12)
    assert parent[chapter_key(16)] == b'\0'
    return advance_no_reports(parent, child, bytes(7), digest(4*digest(b'\0')+digest(bytes(3))))


def verify_observations(lines):
    """Compare all successor bytes to independently advanced maps; observations never seed the next answer."""
    assert len(lines) == 42, 'two original parents, twenty children and twenty successors required'
    roots, input_hashes = [], []
    for chain in range(2):
        start = chain*21
        assert lines[start].startswith('P ')
        original = bytes.fromhex(lines[start][2:])
        expected = decode_checkpoint(original)
        # Complete schemas contain exactly sixteen globals and two current 105-byte metadata rows.
        assert {chapter_key(i) for i in range(1, 17)} <= expected.keys()
        assert all(len(expected[chapter_service(255, sid)]) == 105 for sid in (42, 99))
        assert len(expected) == (18 if chain == 0 else 30)
        assert chapter_key(250) not in expected
        input_hashes.append(hashlib.sha256(original).hexdigest())
        chain_roots = []
        for index in range(10):
            block, observed = lines[start+1+2*index:start+3+2*index]
            assert block.startswith('B ') and observed.startswith('O ')
            child = bytes.fromhex(block[2:])
            # Compute the entire expected state without decoding or reading any actual successor fields.
            expected = successor(expected, child)
            calculated = checkpoint(list(expected.items()))
            actual = bytes.fromhex(observed[2:])
            assert actual == calculated, f'whole-map mismatch chain={chain} slot={index+2}'
            chain_roots.append(tree(list(expected.items()))[0].hex())
            input_hashes.append(hashlib.sha256(child).hexdigest())
        roots.append(chain_roots)
    return dict(transitions=20, original_entries=[18, 30], roots=roots,
                inputs_sha256=input_hashes,
                observations_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
