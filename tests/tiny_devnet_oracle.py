# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map Tiny devnet transcript, frozen before any validator starts.

The native genesis ring commitment is an attributed initial configuration input, not a
Ring/KZG oracle. All other original entries, Thin signatures, headers and every successor
mapping are calculated by the existing mathematical references without STF observations.
"""
import hashlib
import json
from current_stf_epoch_oracle import consensus, successor, PUBLIC
from current_stf_oracle import checkpoint, tree
from report_fixtures import openssl_sign
from state_layout_oracle import chapter_key, digest
from state_consensus_oracle import wire as consensus_wire
from state_history_oracle import wire as history_wire
from state_privileges_oracle import wire as privilege_wire
from state_statistics_oracle import wire as statistics_wire
from test_codec import reference_encode as natural

WIDTHS = (8,8,8,2,4,4,8,8,8,8,2,2,2,2,4,2,2,2,2,2,2,4,4,4,4,4,4,4,4)
VALUES = (10,1,100,2,32,12,10000000,50000000,1000000000,20000000,
          8,16,8,3,24,8,6,80,4,128,5,64000,13791360,4000000,3072,49152,128,3072,10)


def original(configuration):
    """Check every genesis field independently, retaining only the configured cryptographic ring input."""
    header = bytes.fromhex(configuration['genesis_header'])
    assert header == bytes(297)
    parameters = b''.join(number.to_bytes(width, 'little') for number,width in zip(VALUES,WIDTHS))
    assert bytes.fromhex(configuration['protocol_parameters']) == parameters
    supplied = {bytes.fromhex(key):bytes.fromhex(value) for key,value in configuration['genesis_state'].items()}
    keys = {secret:public for public,secret in PUBLIC.items()}
    records = []
    for index in range(6):
        ed,_ = openssl_sign(bytes([index+16])+bytes(31),b'public-tiny-devnet-genesis')
        records.append(keys[index+1]+ed+bytes(272))
    roster = natural(6)+b''.join(records)
    pending,ring,kind,schedule,contest = consensus(supplied[chapter_key(4)])
    assert pending == records and kind == 1 and not contest
    assert schedule == [records[index % 6][:32] for index in range(12)]
    result = {
        chapter_key(1):bytes(2), chapter_key(2):bytes(5120),
        chapter_key(3):history_wire(([(digest(header)+bytes(68),b'')],[])),
        chapter_key(4):consensus_wire((b''.join(records),ring,1,b''.join(schedule),b'')),
        chapter_key(5):bytes(4),chapter_key(6):bytes(128),
        chapter_key(7):roster,chapter_key(8):roster,chapter_key(9):roster,
        chapter_key(10):bytes(2),chapter_key(11):bytes(4),
        chapter_key(12):privilege_wire((0,0,0,[0,0],[])),
        chapter_key(13):statistics_wire(([(0,)*6]*6,[(0,)*6]*6,[(0,)*8]*2,[])),
        chapter_key(14):bytes(12),chapter_key(15):bytes(12),chapter_key(16):bytes(1),
    }
    assert supplied == result, 'native genesis differs from independently authored initial chapters'
    return result,ring


def plan(configuration, slots):
    """Produce exact signed blocks and whole-map checkpoints before any native author or receiver runs."""
    assert 2 <= slots <= 64
    parent,ring = original(configuration)
    states = [checkpoint(list(parent.items()))]
    blocks,roots = [],[tree(list(parent.items()))[0].hex()]
    for slot in range(1,slots+1):
        wire,parent = successor(parent,slot,[],[],dict(staging=ring))
        blocks.append(wire)
        states.append(checkpoint(list(parent.items())))
        roots.append(tree(list(parent.items()))[0].hex())
    return dict(blocks=blocks,states=states,roots=roots,ring_input=ring.hex())


def freeze(directory, slots):
    """Persist independent expected bytes and their identities before the launcher creates any validator process."""
    configuration = json.loads((directory/'chain.json').read_text())
    expected = plan(configuration,slots)
    folder = directory/'independent'
    folder.mkdir()
    for slot,state in enumerate(expected['states']):
        (folder/f'state-{slot}.bin').write_bytes(state)
    for slot,block in enumerate(expected['blocks'],1):
        (folder/f'block-{slot}.bin').write_bytes(block)
    evidence = dict(graypaper_commit='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d',
        slots=slots,genesis_sha256=hashlib.sha256((directory/'chain.json').read_bytes()).hexdigest(),
        ring_input=expected['ring_input'],roots=expected['roots'],
        block_sha256=[hashlib.sha256(raw).hexdigest() for raw in expected['blocks']],
        checkpoint_sha256=[hashlib.sha256(raw).hexdigest() for raw in expected['states']])
    (folder/'plan.json').write_text(json.dumps(evidence,indent=2)+'\n')
    return expected


def verify(directory, slots, expected):
    """Require all six complete maps at every height and every durable block to equal the frozen independent transcript."""
    assert len(expected['states']) == slots+1
    for index in range(6):
        folder = directory/f'node-{index}'
        for slot,state in enumerate(expected['states']):
            assert (folder/f'state-{slot}.bin').read_bytes() == state, (index,slot,'whole-map mismatch')
        journal = (folder/'blocks.bin').read_bytes()
        wanted = b''.join(len(raw).to_bytes(4,'little')+raw for raw in expected['blocks'])
        assert journal == wanted, (index,'journal differs from independent signatures/blocks')
        assert (folder/'state.bin').read_bytes() == expected['states'][-1]
        output = (folder/'stdout.log').read_text().splitlines()
        for slot,root in enumerate(expected['roots']):
            assert any(line.startswith('DEVNET_BLOCK ') and f' slot={slot} ' in line
                       and line.endswith(' root='+root) for line in output), (index,slot,'missing observed root')
    return dict(whole_maps=6*(slots+1),signed_blocks=6*slots,independent=True,
                ring_commitment='attributed genesis input; not independently calculated')
