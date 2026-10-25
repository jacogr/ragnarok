# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-profile guarantees, strict683/684 quorums and nonempty storage/yield/rollback guest siblings."""
from functools import cache
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_profile_oracle as full
import current_stf_report_guests_oracle as guests
from current_stf_effects_oracle import COMMITMENT, guest_gas
from current_stf_oracle import Reader, checkpoint, history, tree
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account_parse, wire as account_wire
from state_history_oracle import wire as history_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire
from state_availability_oracle import wire as availability_wire
from state_workqueues_oracle import wire as queue_wire
from report_oracle import encode as report_wire
from guarantees_oracle import wire as guarantees_wire
from report_fixtures import openssl_sign, validate_provider
from test_codec import reference_encode as natural
from test_bandersnatch_thin_reference import G, IDENTITY, add, encode

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-guests.json'
RING = Path(__file__).parent/'fixtures/jam-full-guest-ring-input.json'
MODES = ('create','panic-rollback','checkpoint-panic')
CORE = 340


@cache
def signed(index, domain, target):
    """Independent OpenSSL signatures use public deterministic distinct32-byte seeds, without a native signer."""
    assert 0 <= index < full.VALIDATORS
    seed = hashlib.sha256(b'ragnarok-full-guest-ed25519'+index.to_bytes(4,'little')).digest()
    return openssl_sign(seed,domain+target)


@cache
def roster_records():
    """Calculate1023 distinct Bandersnatch points and Ed25519 keys, retaining complete opaque record tails."""
    validate_provider()
    source = Reader(full.original()[chapter_key(8)])
    assert source.count() == full.VALIDATORS
    original = [source.take(336) for _ in range(full.VALIDATORS)]; source.done()
    records = []; point = IDENTITY
    # Sequential group addition independently constructs every nonzero scalar/public-key pair.
    for index in range(full.VALIDATORS):
        point = add(point,G)
        records.append(encode(point)+signed(index,b'fixture_full_roster',b'')[0]+original[index][64:])
    assert len({row[:32] for row in records}) == len({row[32:64] for row in records}) == full.VALIDATORS
    return tuple(records)


def original(mode):
    """Bind full geometry to exact independent guest namespaces and a fully distinct validator roster."""
    parent = full.original(); globals = {chapter_key(index) for index in range(1,17)}
    parent = {key:value for key,value in parent.items() if key in globals}
    parent.update({key:value for key,value in guests.original(mode).items() if key not in globals})
    # Both retained guest accounts satisfy the canonical deposit geometry before execution.
    for service in (42,99):
        key = chapter_service(255,service); code,wide,narrow = account_parse(parent[key],105)
        wide = list(wide); wide[0] = 1000000 # Canonical GP deposits are fully funded before any guest write is attempted.
        parent[key] = account_wire((code,wide,narrow))
    records = roster_records(); roster = natural(full.VALIDATORS)+b''.join(records)
    witness = json.loads(RING.read_text())
    assert witness['capacity'] == full.VALIDATORS
    assert witness['members_sha256'] == hashlib.sha256(b''.join(row[:32] for row in records)).hexdigest()
    assert witness['records_sha256'] == hashlib.sha256(b''.join(records)).hexdigest()
    assert witness['bandersnatch_pins_sha256'] == hashlib.sha256(Path('spec/bandersnatch-pins.json').read_bytes()).hexdigest()
    # Initial staging, active and previous rosters share identical distinct ordinal records.
    for chapter in (7,8,9): parent[chapter_key(chapter)] = roster
    schedule = b''.join(records[int.from_bytes(digest(bytes(32)+slot.to_bytes(4,'little'))[:4],'little') % full.VALIDATORS][:32] for slot in range(full.EPOCH))
    parent[chapter_key(4)] = roster+bytes.fromhex(witness['commitment'])+b'\1'+schedule+b'\0'
    return parent


def guarantee(parent, initial):
    """A real high-core report binds the seed anchor/root, full erasure population and two independently signed assigned indices."""
    slot = 3; fixed = history(initial[chapter_key(3)])[0][-1][0]
    anchor = fixed[:32]+fixed[96:100]+tree(list(initial.items()))[0]
    source = Reader(parent[chapter_key(1)]); pools = [source.take(32*source.count()) for _ in range(full.CORES)]; source.done()
    package = digest(b'full-profile guest report'+tree(list(initial.items()))[0])
    header = (package+(100+slot+CORE).to_bytes(4,'little')+digest(package+b'segments')
              +full.VALIDATORS.to_bytes(2,'little')+digest(package+b'exports')+(3+CORE).to_bytes(2,'little')
              +anchor+fixed[32:64]+anchor)
    layout = dict(header=header, prerequisites=b'', core=CORE, authorizer=pools[CORE][:32],
                  gas=17+CORE, auth=b'auth'+bytes([CORE % 256]), lookup=b'',
                  digests=[(99,account_parse(parent[chapter_service(255,99)],105)[0],
                            digest(package+b'payload'),100000,0,bytes([slot,CORE % 256]),
                            (13+CORE,2+CORE,3+CORE,4+CORE,5+CORE))])
    raw = report_wire(layout)
    order = guests.permutation(parent[chapter_key(6)][64:96],full.VALIDATORS)
    indices = [index for index,position in enumerate(order) if (position//3+(slot % full.EPOCH)//10) % full.CORES == CORE]
    assert len(indices) == 3
    return dict(report=raw,slot=slot,layout=layout,
                credentials=[(index,signed(index,b'jam_guarantee',digest(raw))[1]) for index in indices[:2]])


def assurances(parent,count):
    """Use all43 canonical bit bytes and683 genuinely distinct validator signatures for strict full-population quorum."""
    assert count in (0,683,684)
    anchor = history(parent[chapter_key(3)])[0][-1][0][:32]
    bits = (1 << CORE).to_bytes(43,'little')
    target = digest(anchor+bits)
    return [dict(anchor=anchor,bits=bits,index=index,signature=signed(index,b'jam_available',target)[1]) for index in range(count)]


def body(gs,ass):
    """Independently encode and commit full-profile guarantee projections and exact assurance tuples."""
    votes = natural(len(ass))+b''.join(item['anchor']+item['bits']+item['index'].to_bytes(2,'little')+item['signature'] for item in ass)
    hashes = natural(len(gs))+b''.join(digest(item['report'])+item['slot'].to_bytes(4,'little')+natural(len(item['credentials']))
                       +b''.join(index.to_bytes(2,'little')+signature for index,signature in item['credentials']) for item in gs)
    raw = b'\0\0'+guarantees_wire(gs)+votes+bytes(3)
    commitment = digest(2*digest(b'\0')+digest(hashes)+digest(votes)+digest(bytes(3)))
    return raw,commitment


def advance(parent,initial,mode,slot,gs,ass,stored):
    """Compose independent admission, availability, full statistics and literal guest effects over the full foundation."""
    released = slot == 4
    assert len(ass) >= 683 if released else not ass
    outputs = ((99,COMMITMENT),) if released and mode != 'panic-rollback' else ()
    raw,commitment = body(gs,ass)
    author = int.from_bytes(digest(bytes(32)+slot.to_bytes(4,'little'))[:4],'little') % full.VALIDATORS
    wire,result = full.child(parent,body=raw,extrinsic_root=commitment,outputs=outputs,author=author,secret=author+1)
    assert int.from_bytes(wire[96:100],'little') == slot
    old = [None]*full.CORES
    # Only the guarantee-bearing child leaves a pending assignment; the next quorum releases it.
    if slot == 3: old[CORE] = dict(guarantee={key:gs[0][key] for key in ('report','slot','credentials')},registered=slot)
    result[chapter_key(10)] = availability_wire(old)
    pools = Reader(parent[chapter_key(1)]); rows = []; queues = parent[chapter_key(2)]
    # Calculate every pool independently, removing incoming authorizers before queue appends.
    for core in range(full.CORES):
        row = [pools.take(32) for _ in range(pools.count())]
        # A guarantee consumes only its own core authorizer.
        for item in gs:
            if item['layout']['core'] == core:
                assert item['layout']['authorizer'] in row
                row.remove(item['layout']['authorizer'])
        offset = (core*80+slot % 80)*32
        row = (row+[queues[offset:offset+32]])[-8:]
        rows.append(natural(len(row))+b''.join(row))
    pools.done(); result[chapter_key(1)] = b''.join(rows)
    blocks,peaks = history(result[chapter_key(3)])
    blocks[-1] = (blocks[-1][0],b''.join(sorted(item['layout']['header'][:32]+item['layout']['header'][70:102] for item in gs)))
    result[chapter_key(3)] = history_wire((blocks,peaks))
    accumulated = Reader(parent[chapter_key(15)]); ring = [accumulated.take(32*accumulated.count()) for _ in range(full.EPOCH)]; accumulated.done()
    result[chapter_key(15)] = queue_wire('A',ring[1:]+[stored['report'][:32] if released else b''])
    (current,previous,_,_),_ = statistics_parse(result[chapter_key(13)],(full.CORES,full.VALIDATORS,full.VALIDATORS,2**64-1,2**64-1))
    # Reporter statistics count each distinct guarantor once in this block.
    for index in {index for item in gs for index,_ in item['credentials']}:
        row = list(current[index]); row[4] += 1; current[index] = tuple(row)
    # Each authenticated vote contributes to its signer even when the report was already qualified.
    for item in ass:
        row = list(current[item['index']]); row[5] += 1; current[item['index']] = tuple(row)
    cores = [[0]*8 for _ in range(full.CORES)]; activity = {}
    # Incoming reports contribute refinement and per-core load independently of later availability.
    for item in gs:
        layout = item['layout']; load = layout['digests'][0][-1]
        cores[CORE][2:] = [*load[1:],int.from_bytes(layout['header'][32:36],'little'),load[0]]
        row = activity.setdefault(99,[99]+[0]*11); row[3] += 1
        for index,amount in enumerate(load,4): row[index] += amount
    cores[CORE][1] = len(ass)
    # Literal guest behavior determines namespaces, retained gas and activity after release.
    if released:
        report = stored['report']; cores[CORE][0] = int.from_bytes(report[32:36],'little')+4104*((65*int.from_bytes(report[102:104],'little')+63)//64)
        applied = guests.guest_effect(result,parent,mode,99,1,slot)
        row = activity.setdefault(99,[99]+[0]*11)
        for index in range(1,12): row[index] += applied[index]
    result[chapter_key(13)] = statistics_wire((current,previous,cores,[tuple(activity[sid]) for sid in sorted(activity)]))
    return wire,result


def expected_observations(check_frozen=True):
    """Calculate full unique-key report/guest siblings and original-last complete maps before any native execution."""
    lines,roots,hashes = [],[],[]
    # Each isolated chain starts with its own complete guest seed and matching original profile.
    for mode in MODES:
        initial = original(mode); parent = dict(initial); stored = None
        lines.append('P '+checkpoint(list(parent.items())).hex()); roots.append([]); hashes.append([])
        # One honest child proves the seed anchor before admission and sibling availability.
        for slot in (2,3,4):
            gs = [guarantee(parent,initial)] if slot == 3 else []
            # Preserve the admitted report as the independent later availability operand.
            if gs: stored = gs[0]
            ass = assurances(parent,683 if slot == 4 else 0)
            # The extra genuine vote creates a valid depth-one sibling before original-last replay.
            if slot == 4:
                variant,changed = advance(parent,initial,mode,slot,[],assurances(parent,684),stored)
                lines.extend(('V '+variant.hex(),'O '+checkpoint(list(changed.items())).hex()))
                roots[-1].append(tree(list(changed.items()))[0].hex())
            wire,result = advance(parent,initial,mode,slot,gs,ass,stored)
            # Equal qualified effects must differ only in signed identity and vote statistics.
            if slot == 4: assert {key for key in result if result[key] != changed[key]} == {chapter_key(3),chapter_key(13)}
            encoded = checkpoint(list(result.items())); lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(result.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest()); parent = result
    evidence = dict(graypaper_commit=full.GP,chains=3,transitions=12,sibling_imports=3,
                    full_profile_sha256=hashlib.sha256(full.FIXTURE.read_bytes()).hexdigest(),guest_reference_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),
                    ring_input_sha256=hashlib.sha256(RING.read_bytes()).hexdigest(),successor_roots=roots,original_checkpoint_sha256=hashes,
                    guest_gas={mode:guest_gas(mode) for mode in MODES},expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    # Never substitute a native observation for the precommitted independent stream digest.
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
