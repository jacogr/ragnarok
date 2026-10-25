# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-profile guest-bearing epoch crossings and1023-to1020 population rotation."""
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_profile_oracle as full
import jam_fuzzer_full_guests_oracle as guests
from current_stf_oracle import Reader, checkpoint, history, sign, tree
from header_oracle import wire as header_wire
from state_layout_oracle import chapter_key, digest
from state_consensus_oracle import wire as consensus_wire
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-epochs.json'
RING = Path(__file__).parent/'fixtures/jam-full-epoch-ring-input.json'
SLOTS = ((599,600,601,1199,1200,1201),(1199,1200,1201))


def roster(data):
    """Preserve every full opaque record while decoding independently bounded population counts."""
    source = Reader(data); count = source.count()
    assert count in (1020,1023)
    result = [source.take(336) for _ in range(count)]; source.done()
    return result


def original():
    """Change only staged population and observable previous order before calculating guest admission roots."""
    parent = guests.original('create'); records = guests.roster_records()
    staged = list(reversed(records[:1020]))
    parent[chapter_key(7)] = natural(len(staged))+b''.join(staged)
    previous = records[333:]+records[:333]
    parent[chapter_key(9)] = natural(len(previous))+b''.join(previous)
    return parent


def successor(parent,slot):
    """Sign full variable epoch markers and calculate every rotated chapter from independent parent bytes."""
    previous = int.from_bytes(parent[chapter_key(11)],'little'); crossed = slot//600 > previous//600
    source = Reader(parent[chapter_key(4)])
    pending = [source.take(336) for _ in range(source.count())]; root = source.take(144)
    assert source.take(1) == b'\1'
    schedule = [source.take(32) for _ in range(600)]
    assert source.count() == 0; source.done()
    entropy = parent[chapter_key(6)]; epoch = None
    active = roster(parent[chapter_key(8)])
    # A crossing consumes the old pending population, then publishes the staged roster and its attributed input root.
    if crossed:
        active,pending = pending,roster(parent[chapter_key(7)])
        witness = json.loads(RING.read_text())
        assert witness['capacity'] == 1023 and witness['population'] == len(pending)
        assert witness['members_sha256'] == hashlib.sha256(b''.join(row[:32] for row in pending)).hexdigest()
        assert witness['bandersnatch_pins_sha256'] == hashlib.sha256(Path('spec/bandersnatch-pins.json').read_bytes()).hexdigest()
        root = bytes.fromhex(witness['commitment'])
        seed = entropy[32:64]
        schedule = [active[int.from_bytes(digest(seed+i.to_bytes(4,'little'))[:4],'little') % len(active)][:32] for i in range(600)]
        epoch = dict(entropy=entropy[:32],tickets_entropy=entropy[32:64],validators=[dict(bandersnatch=row[:32],ed25519=row[32:64]) for row in pending])
    selected = schedule[slot % 600]
    author = next(index for index,row in enumerate(active) if row[:32] == selected)
    secret = next(index+1 for index,row in enumerate(guests.roster_records()) if row[:32] == selected)
    context = b'jam_fallback_seal'+(entropy[64:96] if crossed else entropy[96:128])
    _,selected_output = sign(secret,context,b'')
    proof,entropy_output = sign(secret,b'jam_entropy'+selected_output,b'')
    value = dict(parent=history(parent[chapter_key(3)])[0][-1][0][:32],parent_state_root=tree(list(parent.items()))[0],
                 extrinsic_hash=digest(4*digest(b'\0')+digest(bytes(3))),slot=slot,epoch_mark=epoch,tickets_mark=None,
                 author_index=author,entropy_source=proof,offenders_mark=[])
    value['seal'],_ = sign(secret,context,header_wire('U',value))
    header = header_wire('H',value)
    result = full.successor(parent,header,entropy_output,author=author)
    result[chapter_key(4)] = consensus_wire((b''.join(pending),root,1,b''.join(schedule),b''))
    # Both complete records and statistics retain the former active population at the crossing.
    if crossed:
        result[chapter_key(8)] = natural(len(active))+b''.join(active)
        result[chapter_key(9)] = parent[chapter_key(8)]
    return header+bytes(7),result


def expected_observations(check_frozen=True):
    """Freeze guest effects followed by ordinary/skipped-tail full epochs without reading native successors."""
    lines,roots,hashes = [],[],[]
    # Both independent chains execute a genuine guest before crossing; one skips the entire first tail.
    for slots in SLOTS:
        initial = original(); parent = initial; stored = None
        lines.append('P '+checkpoint(list(parent.items())).hex()); roots.append([]); hashes.append([])
        for slot in (2,3,4)+slots:
            # Admission/quorum arithmetic is unchanged before the first full epoch transition.
            if slot < 600 and slot in (2,3,4):
                gs = [guests.guarantee(parent,initial)] if slot == 3 else []
                if gs: stored = gs[0] # The later quorum consumes exactly this independently admitted report.
                wire,parent = guests.advance(parent,initial,'create',slot,gs,guests.assurances(parent,683 if slot == 4 else 0),stored)
            else:
                wire,parent = successor(parent,slot) # Complete epoch headers retain their actual variable extent.
            encoded = checkpoint(list(parent.items()));lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    evidence = dict(graypaper_commit=full.GP,chains=2,transitions=15,slots=[list((2,3,4)+slots) for slots in SLOTS],
                    full_guests_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),ring_input_sha256=hashlib.sha256(RING.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    # Calculated expectations become immutable before any backend or upstream process observes them.
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
