# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Issue215 expected signatures and complete maps calculated before target startup; only KZG seed roots are attributed."""
import hashlib
import json
from functools import cache
from pathlib import Path
import jam_fuzzer_full_profile_oracle as full
import jam_fuzzer_full_guests_oracle as reports
import current_stf_report_guests_oracle as guests
import current_stf_preimage_aging_oracle as aging
from state_requests_oracle import key as request_key, wire as request_wire
from state_layout_oracle import chapter_service
from state_accounts_oracle import parse as account_parse, wire as account_wire
from current_stf_transfers_oracle import original as tiny_original
from current_stf_oracle import Reader, checkpoint, history, sign, tree
from header_oracle import wire as header_wire
from state_layout_oracle import chapter_key, digest
from state_consensus_oracle import wire as consensus_wire
from state_privileges_oracle import wire as privileges_wire
from state_statistics_oracle import wire as statistics_wire
from test_codec import reference_encode as natural
from test_bandersnatch_thin_reference import G, IDENTITY, add, encode

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-network.json'
RING = Path(__file__).parent/'fixtures/jam-network-ring-input.json'
CORES, VALIDATORS, EPOCH = 85, 255, 60
VALUES = (10,1,100,85,900,60,10000000,50000000,1250000000,875000000,
          8,16,8,4,600,8,6,80,5,128,5,64000,13791360,4000000,3072,49152,128,3072,50)
PLANS = ((59,60,61,119,120,121),(120,121,180,181))


def parameters():
    """Encode all29 independent Appendix B fields; exactly nine differ from Full."""
    return b''.join(value.to_bytes(width,'little') for value,width in zip(VALUES,full.WIDTHS))


@cache
def records():
    """Calculate255 distinct scalar/public pairs; preserve opaque record tails from the independent seed."""
    seed = tiny_original('halt'); source = Reader(seed[chapter_key(8)])
    rows = [source.take(336) for _ in range(source.count())]; source.done()
    point = IDENTITY; result = []
    for index in range(VALIDATORS):
        # Pure group arithmetic supplies each signing key independently from the native primitive.
        point = add(point,G)
        result.append(encode(point)+reports.signed(index,b'fixture_full_roster',b'')[0]+rows[index % len(rows)][64:])
    return tuple(result)


def commitment(rows):
    """Use only a pinned crypto input witness, never a native STF observation or expected state."""
    witness = json.loads(RING.read_text())
    assert witness['capacity'] == VALIDATORS
    assert witness['bandersnatch_pins_sha256'] == hashlib.sha256(Path('spec/bandersnatch-pins.json').read_bytes()).hexdigest()
    key = hashlib.sha256(b''.join(row[:32] for row in rows)).hexdigest()
    return bytes.fromhex(witness['commitments'][key])


def original(population):
    """Construct every global chapter at85/255/60 and stage a different valid GP population."""
    parent = tiny_original('halt'); rows = records(); roster = natural(VALIDATORS)+b''.join(rows)
    staged = tuple(reversed(rows[:population]))
    schedule = b''.join(rows[int.from_bytes(digest(bytes(32)+slot.to_bytes(4,'little'))[:4],'little') % VALIDATORS][:32] for slot in range(EPOCH))
    parent[chapter_key(4)] = roster+commitment(rows)+b'\1'+schedule+b'\0'
    parent[chapter_key(7)] = natural(population)+b''.join(staged)
    parent[chapter_key(8)] = parent[chapter_key(9)] = roster
    parent[chapter_key(1)] = b''.join(natural(core % 9)+b''.join(digest(b'network-pool'+bytes([core,index])) for index in range(core % 9)) for core in range(CORES))
    parent[chapter_key(2)] = b''.join(digest(b'network-queue'+bytes([core,index])) for core in range(CORES) for index in range(80))
    parent[chapter_key(10)] = bytes(CORES)
    parent[chapter_key(12)] = privileges_wire((42,99,42,[42 if core % 2 == 0 else 99 for core in range(CORES)],[]))
    parent[chapter_key(13)] = statistics_wire(([(index+1,0,0,0,0,0) for index in range(VALIDATORS)],[(0,)*6]*VALIDATORS,[(0,)*8]*CORES,[]))
    parent[chapter_key(14)] = parent[chapter_key(15)] = bytes(EPOCH)
    return parent


def roster(raw):
    """Decode only complete336-byte records in an independently owned map."""
    source = Reader(raw); rows = [source.take(336) for _ in range(source.count())]; source.done()
    return rows


def successor(parent, slot):
    """Calculate delayed population activation, variable markers and every posterior map without executing the client."""
    prior = int.from_bytes(parent[chapter_key(11)],'little'); assert prior < slot
    source = Reader(parent[chapter_key(4)])
    pending = [source.take(336) for _ in range(source.count())]; root = source.take(144)
    assert source.take(1) == b'\1'
    schedule = [source.take(32) for _ in range(EPOCH)]; assert source.count() == 0; source.done()
    active = roster(parent[chapter_key(8)]); entropy = parent[chapter_key(6)]; marker = None
    crossed = slot//EPOCH > prior//EPOCH
    if crossed:
        # Each imported crossing performs one rotation, even when the slot skips several epochs.
        active,pending = pending,roster(parent[chapter_key(7)]); root = commitment(pending)
        schedule = [active[int.from_bytes(digest(entropy[32:64]+index.to_bytes(4,'little'))[:4],'little') % len(active)][:32] for index in range(EPOCH)]
        marker = dict(entropy=entropy[:32],tickets_entropy=entropy[32:64],validators=[dict(bandersnatch=row[:32],ed25519=row[32:64]) for row in pending])
    selected = schedule[slot % EPOCH]; author = next(index for index,row in enumerate(active) if row[:32] == selected)
    secret = next(index+1 for index,row in enumerate(records()) if row[:32] == selected)
    context = b'jam_fallback_seal'+(entropy[64:96] if crossed else entropy[96:128])
    _,output = sign(secret,context,b''); proof,entropy_output = sign(secret,b'jam_entropy'+output,b'')
    fields = dict(parent=history(parent[chapter_key(3)])[0][-1][0][:32],parent_state_root=tree(list(parent.items()))[0],extrinsic_hash=digest(4*digest(b'\0')+digest(bytes(3))),slot=slot,epoch_mark=marker,tickets_mark=None,author_index=author,entropy_source=proof,offenders_mark=[])
    fields['seal'],_ = sign(secret,context,header_wire('U',fields)); header = header_wire('H',fields)
    result = full.successor(parent,header,entropy_output,author=author,cores=CORES,epoch=EPOCH)
    result[chapter_key(4)] = consensus_wire((b''.join(pending),root,1,b''.join(schedule),b''))
    if crossed:
        result[chapter_key(8)] = natural(len(active))+b''.join(active)
        result[chapter_key(9)] = parent[chapter_key(8)]
    return header+bytes(7),result



def child(parent, *, body=bytes(7), extrinsic_root=None, outputs=(), author=0, secret=1, offenders=()):
    """Sign a same-epoch nonempty child and calculate geometry-specific base effects independently."""
    slot = int.from_bytes(parent[chapter_key(11)],'little')+1
    source = Reader(parent[chapter_key(4)])
    source.take(336*source.count()); source.take(144); assert source.take(1) == b'\1'
    schedule = [source.take(32) for _ in range(EPOCH)]; active = roster(parent[chapter_key(8)])
    selected = schedule[slot % EPOCH]
    author = next(index for index,row in enumerate(active) if row[:32] == selected)
    secret = next(index+1 for index,row in enumerate(records()) if row[:32] == selected)
    wire,entropy_output = full.sealed_child(parent,body=body,extrinsic_root=extrinsic_root,author=author,secret=secret,offenders=offenders,epoch=EPOCH,validators=VALIDATORS)
    return wire,full.successor(parent,wire[:-len(body)],entropy_output,outputs=outputs,author=author,cores=CORES,epoch=EPOCH)


def guest_original(mode):
    """Combine independently authored guest namespaces with the exact new preset and fully funded accounts."""
    parent = original(252); globals = {chapter_key(index) for index in range(1,17)}
    parent = {key:value for key,value in parent.items() if key in globals}
    parent.update({key:value for key,value in guests.original(mode).items() if key not in globals})
    for service in (42,99):
        key = chapter_service(255,service); code,wide,narrow = account_parse(parent[key],105)
        wide = list(wide); wide[0] = 1000000
        parent[key] = account_wire((code,wide,narrow))
    return parent

def expected_observations(check_frozen=True):
    """Freeze67 signed successors across ordinary/skipped epochs and255-to252/6 delayed activation."""
    lines,roots,hashes,traces = [],[],[],[]
    for population in (252,6):
        for slots in PLANS:
            parent = original(population); lines.append('P '+checkpoint(list(parent.items())).hex())
            roots.append([]); hashes.append([])
            for slot in slots:
                # Every expected signature and complete map exists before any native process starts.
                wire,parent = successor(parent,slot); encoded = checkpoint(list(parent.items()))
                lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
                roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    # Nonempty guarantees and171/172-vote availability siblings execute literal guests under the same preset.
    import sys
    profile = sys.modules[__name__]
    for mode in reports.MODES:
        initial = guest_original(mode); parent = initial; stored = None
        lines.append('P '+checkpoint(list(parent.items())).hex()); roots.append([]); hashes.append([])
        for slot in (2,3,4):
            gs = [reports.guarantee(parent,initial,core=84,profile=profile)] if slot == 3 else []
            if gs: stored = gs[0]
            ass = reports.assurances(parent,171 if slot == 4 else 0,cores=(84,),profile=profile)
            if slot == 4:
                variant,changed = reports.advance(parent,initial,mode,slot,[],
                    reports.assurances(parent,172,cores=(84,),profile=profile),stored,profile=profile,target_core=84)
                encoded = checkpoint(list(changed.items())); lines.extend(('V '+variant.hex(),'O '+encoded.hex()))
                roots[-1].append(tree(list(changed.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
            wire,parent = reports.advance(parent,initial,mode,slot,gs,ass,stored,profile=profile,target_core=84)
            encoded = checkpoint(list(parent.items())); lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    # Independent exact D900 and strict D900+1 releases exercise expiry, restoration and guest rollback.
    for mode in aging.PROFILES:
        for release in (932,933):
            parent = original(252); globals = {chapter_key(index) for index in range(1,17)}
            parent = {key:value for key,value in parent.items() if key in globals}
            parent.update({key:value for key,value in aging.original(mode).items() if key not in globals})
            key = request_key(99,digest(aging.PAYLOAD),1)
            parent[key] = request_wire((0,) if mode == 'live' else (0,32))
            for service in (42,99):
                account = chapter_service(255,service); code,wide,narrow = account_parse(parent[account],105)
                wide = list(wide); wide[0] = 1000000; parent[account] = account_wire((code,wide,narrow))
            seed,parent = successor(parent,929); initial = parent; stored = None
            lines.extend(('H '+seed[:-7].hex(),'P '+checkpoint(list(parent.items())).hex()))
            roots.append([]); hashes.append([]); traces.append([])
            def apply_expiry(result,before,profile_mode,service,invocations,slot):
                """Literal age/history/account equations and instruction gas are independent of the native STF."""
                trace = aging.effects(result,before,profile_mode,slot,100000,
                    statistics_config=(CORES,VALIDATORS,VALIDATORS,2**64-1,2**64-1),expunge_period=900)
                traces[-1].append(trace)
                activity = [99]+[0]*11; activity[9] = 1; activity[11] = trace['gas']
                return activity
            for slot in range(930,release+1):
                admission = release-1
                gs = [reports.guarantee(parent,initial,slot=slot,core=84,profile=profile)] if slot == admission else []
                if gs: stored = gs[0]
                ass = reports.assurances(parent,171 if slot == release else 0,cores=(84,),profile=profile)
                wire,parent = reports.advance(parent,initial,mode,slot,gs,ass,stored,admission_slot=admission,
                    profile=profile,target_core=84,guest_effect=apply_expiry,guest_outputs=())
                encoded = checkpoint(list(parent.items())); lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
                roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    evidence = dict(parameters=parameters().hex(), cores=CORES, validators=VALIDATORS, epoch_slots=EPOCH,
                    chains=17,transitions=67,expiry_traces=json.loads(json.dumps(traces)),sibling_imports=3,successor_roots=roots,successor_checkpoint_sha256=hashes,
                    ring_input_sha256=hashlib.sha256(RING.read_bytes()).hexdigest(),
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
