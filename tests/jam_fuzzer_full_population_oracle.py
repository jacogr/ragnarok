# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-population offender nulling, delayed1023-to1020 activation and multi-epoch skips."""
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_offenders_oracle as offenders
import jam_fuzzer_full_tickets_oracle as tickets
import jam_fuzzer_full_guests_oracle as guests
import jam_fuzzer_full_profile_oracle as full
from current_stf_epoch_oracle import NULL_VALIDATOR
from current_stf_oracle import checkpoint,history,sign,tree
from header_oracle import wire as header_wire
from state_layout_oracle import chapter_key,digest
from state_consensus_oracle import wire as consensus_wire
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-population.json'
RING = Path(__file__).parent/'fixtures/jam-full-population-ring-input.json'
PLANS = ((599,600,601,1199,1200,1201),(1200,1201,1799,1800,1801))


def original():
    """Stage a reversed1020-member population before genuine offender evidence is admitted into the complete seed."""
    parent = offenders.original();staged = list(reversed(guests.roster_records()[:1020]))
    parent[chapter_key(7)] = natural(len(staged))+b''.join(staged)
    return parent


def prelude(parent):
    """Execute independently authored evidence before epoch rotation; no supplied posterior Phi is fabricated."""
    first = offenders.payload(culprits=[offenders.culprit(0),offenders.culprit(1022)],
                             faults=[offenders.fault(511),offenders.fault(1022,offenders.BAD,True)])
    result = []
    for slot,value in ((2,first),(3,offenders.payload(faults=[offenders.fault(510)]))):
        wire,parent = offenders.advance(parent,slot,value);result.append((wire,parent))
    return result


def successor(parent,slot,*,unfiltered_marker=False):
    """Apply one GP population rotation per imported crossing, retain former active records/statistics and sign real fallback credentials."""
    previous = int.from_bytes(parent[chapter_key(11)],'little');assert previous < slot
    pending,root,kind,schedule,accumulated = tickets.consensus(parent[chapter_key(4)])
    assert kind == 1 and not accumulated
    active = offenders.roster(parent[chapter_key(8)]);entropy = parent[chapter_key(6)]
    crossed = slot//600 > previous//600;epoch = None
    # Incoming pending keys are nulled from posterior Phi; the old pending sequence alone becomes active.
    if crossed:
        active = pending;staged = offenders.roster(parent[chapter_key(7)])
        phi = offenders.judgments(parent[chapter_key(5)])[3]
        pending = [NULL_VALIDATOR if row[32:64] in phi else row for row in staged]
        witness = json.loads(RING.read_text())
        assert witness['capacity'] == 1023 and witness['population'] == len(pending) == 1020
        assert witness['null_records'] == sum(row == NULL_VALIDATOR for row in pending) == 4
        assert witness['members_sha256'] == hashlib.sha256(b''.join(row[:32] for row in pending)).hexdigest()
        assert witness['records_sha256'] == hashlib.sha256(b''.join(pending)).hexdigest()
        assert witness['bandersnatch_pins_sha256'] == hashlib.sha256(Path('spec/bandersnatch-pins.json').read_bytes()).hexdigest()
        root = bytes.fromhex(witness['commitment']);seed = entropy[32:64]
        schedule = [active[int.from_bytes(digest(seed+index.to_bytes(4,'little'))[:4],'little') % len(active)][:32]
                    for index in range(600)]
        announced = staged if unfiltered_marker else pending
        epoch = dict(entropy=entropy[:32],tickets_entropy=entropy[32:64],validators=[dict(bandersnatch=row[:32],ed25519=row[32:64]) for row in announced])
    else: assert not unfiltered_marker
    selected = schedule[slot % 600]
    secret = next(index+1 for index,row in enumerate(guests.roster_records()) if row[:32] == selected)
    author = next(index for index,row in enumerate(active) if row[:32] == selected)
    context = b'jam_fallback_seal'+(entropy[64:96] if crossed else entropy[96:128])
    _,output = sign(secret,context,b'');proof,entropy_output = sign(secret,b'jam_entropy'+output,b'')
    value = dict(parent=history(parent[chapter_key(3)])[0][-1][0][:32],parent_state_root=tree(list(parent.items()))[0],
                 extrinsic_hash=digest(4*digest(b'\0')+digest(bytes(3))),slot=slot,epoch_mark=epoch,tickets_mark=None,
                 author_index=author,entropy_source=proof,offenders_mark=[])
    value['seal'],_ = sign(secret,context,header_wire('U',value));header = header_wire('H',value)
    result = full.successor(parent,header,entropy_output,author=author)
    result[chapter_key(4)] = consensus_wire((b''.join(pending),root,kind,b''.join(schedule),b''))
    if crossed:
        result[chapter_key(8)] = natural(len(active))+b''.join(active)
        result[chapter_key(9)] = parent[chapter_key(8)]
    return header+bytes(7),result


def expected_observations(check_frozen=True):
    """Freeze ordinary and two-epoch-skip complete maps, including exact refusal of unfiltered epoch-marker records."""
    lines,roots,hashes = [],[],[]
    for slots in PLANS:
        parent = original();lines.append('P '+checkpoint(list(parent.items())).hex());roots.append([]);hashes.append([])
        # Every chain establishes Phi with real evidence rather than inserting the anticipated posterior set.
        for wire,parent in prelude(parent):
            encoded = checkpoint(list(parent.items()));lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
        first = True
        for slot in slots:
            previous = int.from_bytes(parent[chapter_key(11)],'little');crossed = slot//600 > previous//600
            if first and crossed:
                invalid,_ = successor(parent,slot,unfiltered_marker=True);encoded = checkpoint(list(parent.items()))
                lines.extend(('R '+invalid.hex()+' marker/InvalidEpochMarker','O '+encoded.hex()))
                roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest());first = False
            wire,after = successor(parent,slot);encoded = checkpoint(list(after.items()))
            # Even a two-epoch jump activates only the old pending population, with staged membership delayed again.
            if crossed:
                prior_pending = tickets.consensus(parent[chapter_key(4)])[0]
                assert offenders.roster(after[chapter_key(8)]) == prior_pending
                assert after[chapter_key(9)] == parent[chapter_key(8)]
            assert after[chapter_key(5)] == parent[chapter_key(5)]
            lines.extend(('B '+wire.hex(),'O '+encoded.hex()));parent = after
            roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
        assert len(offenders.roster(parent[chapter_key(8)])) == 1020
        assert sum(row == NULL_VALIDATOR for row in offenders.roster(parent[chapter_key(8)])) == 4
    evidence = dict(graypaper_commit=full.GP,chains=2,transitions=sum(map(len,roots)),accepted=15,refused=2,
                    ring_input_sha256=hashlib.sha256(RING.read_bytes()).hexdigest(),
                    offender_fixture_sha256=hashlib.sha256(offenders.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
