# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP0.8 full-profile empty-body STF maps; the attributed KZG seed is an input, never an observed successor."""
import hashlib
import json
from pathlib import Path
from current_stf_oracle import Reader, checkpoint, history, sign, tree
from current_stf_transfers_oracle import original as tiny_original, FIXTURE as BASE
from current_stf_trace_genesis_oracle import initial_header
from state_layout_oracle import chapter_key, digest
from state_history_oracle import wire as history_wire
from state_statistics_oracle import wire as statistics_wire, parse as statistics_parse
from state_privileges_oracle import wire as privileges_wire
from test_codec import reference_encode as natural
from test_crypto import keccak256
from history_transition_fixtures import output_root

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-profile.json'
RING = Path(__file__).parent/'fixtures/jam-full-ring-input.json'
GP = '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
CORES, VALIDATORS, EPOCH = 341, 1023, 600
WIDTHS = (8,8,8,2,4,4,8,8,8,8,2,2,2,2,4,2,2,2,2,2,2,4,4,4,4,4,4,4,4)
VALUES = (10,1,100,341,19200,600,10000000,50000000,5000000000,3500000000,
          8,16,8,16,14400,8,6,80,10,128,5,64000,13791360,4000000,3072,49152,128,3072,500)


def parameters():
    """Encode every AppendixB field from the pinned definitions, retaining each independent fixed width."""
    result = b''.join(value.to_bytes(width, 'little') for value, width in zip(VALUES, WIDTHS))
    assert len(result) == 122
    return result


def original(dense=False):
    """Author every full-size global chapter and retain the original independent service namespaces unchanged."""
    parent = tiny_original('halt')
    witness = json.loads(RING.read_text())
    assert witness['capacity'] == VALIDATORS
    assert witness['bandersnatch_pins_sha256'] == hashlib.sha256(Path('spec/bandersnatch-pins.json').read_bytes()).hexdigest()
    public = bytes.fromhex(witness['public_key'])
    assert witness['ordered_public_keys_sha256'] == hashlib.sha256(public*VALIDATORS).hexdigest()
    source = Reader(parent[chapter_key(8)])
    count = source.count()
    records = [source.take(336) for _ in range(count)]
    source.done()
    assert count == 6 and records[0][:32] == public
    rows = [public+records[index % count][32:] for index in range(VALIDATORS)]
    roster = natural(VALIDATORS)+b''.join(rows)
    parent[chapter_key(4)] = roster+bytes.fromhex(witness['commitment'])+b'\1'+public*EPOCH+b'\0'
    for chapter in (7, 8, 9):
        parent[chapter_key(chapter)] = roster # Exact opaque records and all1023 ordinal positions remain present.
    pools = []
    for core in range(CORES):
        size = 8 if dense else core % 9
        pools.append(natural(size)+b''.join(digest(b'full-pool'+core.to_bytes(2,'little')+bytes([index])) for index in range(size)))
    parent[chapter_key(1)] = b''.join(pools)
    parent[chapter_key(2)] = b''.join(digest(b'full-queue'+core.to_bytes(2,'little')+bytes([index])) for core in range(CORES) for index in range(80))
    parent[chapter_key(10)] = bytes(CORES)
    parent[chapter_key(12)] = privileges_wire((42,99,42,[42 if core % 2 == 0 else 99 for core in range(CORES)],[]))
    current = [tuple(10*(index+1)+field for field in range(6)) for index in range(VALIDATORS)]
    previous = [tuple(100*(index+1)+field for field in range(6)) for index in range(VALIDATORS)]
    parent[chapter_key(13)] = statistics_wire((current,previous,[(1,2,3,4,5,6,7,8)]*CORES,[(42,)+tuple(range(1,12))]))
    parent[chapter_key(14)] = parent[chapter_key(15)] = bytes(EPOCH)
    assert len(parent[chapter_key(2)]) == CORES*80*32
    assert history(parent[chapter_key(3)])[0][-1][0][:32] == digest(initial_header())
    return parent


def child(parent):
    """Independently sign the next actual full-profile fallback child and its entropy proof under exact GP domains."""
    slot = int.from_bytes(parent[chapter_key(11)], 'little')+1
    assert 1 < slot < EPOCH
    entropy = parent[chapter_key(6)]
    context = b'jam_fallback_seal'+entropy[96:128]
    _, selected = sign(1, context, b'')
    proof, entropy_output = sign(1, b'jam_entropy'+selected, b'')
    commitment = digest(4*digest(b'\0')+digest(bytes(3)))
    parent_hash = history(parent[chapter_key(3)])[0][-1][0][:32]
    unsigned = parent_hash+tree(list(parent.items()))[0]+commitment+slot.to_bytes(4,'little')+bytes(4)+proof+b'\0'
    seal, _ = sign(1, context, unsigned)
    header = unsigned+seal
    assert len(header) == 297
    return header+bytes(7), successor(parent, header, entropy_output)


def successor(parent, header, entropy_output):
    """Calculate full authorization, entropy, history/MMR, clock, outputs and statistics without a native observation."""
    result = dict(parent)
    slot = int.from_bytes(header[96:100], 'little')
    assert slot == int.from_bytes(parent[chapter_key(11)], 'little')+1 and slot < EPOCH
    entropy = parent[chapter_key(6)]
    result[chapter_key(6)] = digest(entropy[:32]+entropy_output)+entropy[32:]
    result[chapter_key(11)] = slot.to_bytes(4, 'little')
    source = Reader(parent[chapter_key(1)]); queues = parent[chapter_key(2)]; pools = []
    for core in range(CORES):
        count = source.count()
        assert count <= 8
        row = source.take(count*32)
        offset = (core*80+slot % 80)*32
        row = (row+queues[offset:offset+32])[-256:]
        pools.append(natural(len(row)//32)+row)
    source.done()
    result[chapter_key(1)] = b''.join(pools)
    blocks, peaks = history(parent[chapter_key(3)])
    assert blocks[-1][0][:32] == header[:32]
    fixed, packages = blocks[-1]
    blocks[-1] = (fixed[:64]+tree(list(parent.items()))[0]+fixed[96:], packages)
    carry = output_root([]); position = 0
    while position < len(peaks) and peaks[position] is not None:
        carry = bytes.fromhex(keccak256(peaks[position]+carry))
        peaks[position] = None; position += 1
    if position == len(peaks): peaks.append(carry)
    else: peaks[position] = carry
    present = [peak for peak in peaks if peak is not None]; bag = present[0]
    for peak in present[1:]: bag = bytes.fromhex(keccak256(b'peak'+bag+peak))
    blocks.append((digest(header)+bag+bytes(32)+slot.to_bytes(4,'little'),b''))
    result[chapter_key(3)] = history_wire((blocks[-8:],peaks))
    (current, previous, _, _), consumed = statistics_parse(parent[chapter_key(13)],(CORES,VALIDATORS,VALIDATORS,2**64-1,2**64-1))
    assert consumed == len(parent[chapter_key(13)])
    row = list(current[0]); row[0] += 1; current[0] = tuple(row)
    result[chapter_key(13)] = statistics_wire((current,previous,[(0,)*8]*CORES,[]))
    result[chapter_key(16)] = b'\0'
    assert set(result) == set(parent)
    return result


def expected_observations(check_frozen=True):
    """Freeze complete sparse/dense full-profile chains before invoking any native STF or socket target."""
    lines, roots, hashes, blocks = [], [], [], []
    for dense in (False, True):
        parent = original(dense); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); blocks.append([])
        for _ in range(9):
            wire, parent = child(parent)
            encoded = checkpoint(list(parent.items()))
            lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex())
            hashes[-1].append(hashlib.sha256(encoded).hexdigest()); blocks[-1].append(hashlib.sha256(wire).hexdigest())
    evidence = dict(graypaper_commit=GP, parameters=parameters().hex(), cores=CORES, validators=VALIDATORS,
                    epoch_slots=EPOCH, transitions=18, chains=2, successor_roots=roots,
                    successor_checkpoint_sha256=hashes, blocks_sha256=blocks,
                    base_sha256=hashlib.sha256(BASE.read_bytes()).hexdigest(), ring_input_sha256=hashlib.sha256(RING.read_bytes()).hexdigest(),
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [], lines, evidence
