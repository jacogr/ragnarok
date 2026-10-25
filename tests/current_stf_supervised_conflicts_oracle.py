# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map parallel supervisor/junior writes, annulment, retained provisions and discarded yields cases."""
import hashlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers
from current_stf_effects_oracle import immediate, envelope, simulate, gas_definitions
from current_stf_reporting_oracle import body, assurances
from current_stf_oracle import checkpoint, tree
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account_parse, wire as account_wire
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire, DEFAULT

FIXTURE = Path(__file__).parent/'fixtures/current-stf-supervised-conflicts.json'
PROFILES = ('conflict', 'supervisor-panic', 'supervisor-checkpoint-panic', 'junior-panic', 'stale-supervisor')
PAYLOAD = b'R'


from current_stf_transfer_memos_oracle import foundation
COMMITMENT = bytes(range(32))


def programs(profile):
    """Both guests mutate42 from the same prior; junior also yields and provides a genuinely pending I payload."""
    junior = [immediate(7, 2**64-1), immediate(8, 196608), immediate(9, 1),
              immediate(10, 196609), immediate(11, 1), bytes([10, 5]),
              immediate(7, 196640), bytes([10, 27]), immediate(7, 2**64-1),
              immediate(8, 196672), immediate(9, 1), bytes([10, 28])]
    junior.append(b'\0' if profile == 'junior-panic' else bytes([50, 0]))
    supervisor = [immediate(7, 42), immediate(8, 196608), immediate(9, 1),
                  immediate(10, 196609), immediate(11, 1), bytes([10, 5])]
    if profile == 'supervisor-checkpoint-panic':
        supervisor.append(bytes([10, 19])) # Only the real selected checkpoint conflicts with the junior.
    supervisor.append(b'\0' if profile in ('supervisor-panic', 'supervisor-checkpoint-panic') else bytes([50, 0]))
    return ((junior, bytes([7,42])+bytes(30)+COMMITMENT+b'I'), (supervisor, bytes([7,99])))


def original(profile):
    """Commit both distinct code identities and actual supervisor incarnation before signing either report."""
    parent = transfers.original('halt')
    for sid, (instructions, memory) in zip((42,99), programs(profile)):
        key = chapter_service(255, sid); old_hash, wide, narrow = account_parse(parent[key], 105)
        old = parent.pop(value_key('P', sid, old_hash)); del parent[request_key(sid, old_hash, len(old))]
        raw = envelope(instructions, memory); hashed = digest(raw)
        parent[value_key('P', sid, hashed)] = raw; parent[request_key(sid, hashed, len(raw))] = request_wire((1,))
        wide, narrow = list(wide), list(narrow); wide[4] += len(raw)-len(old)
        if sid == 42:
            narrow[4] = 99; narrow[5] = int(profile == 'stale-supervisor') # Fallback self supervision cannot annul itself.
        parent[key] = account_wire((hashed, wide, narrow))
    return parent


def effects(result, parent, profile, slot, budget, *, statistics_config=DEFAULT):
    """N preserves junior gas/provisions, discards its selected yield/writes; M uses the surviving supervisor account."""
    own = profile in ('supervisor-panic', 'stale-supervisor'); storage = value_key('S',42,b'\7')
    value = bytes([42 if own else 99]); result[storage] = value
    key = chapter_service(255,42); code,wide,narrow = account_parse(parent[key],105)
    wide,narrow = list(wide),list(narrow)
    if storage not in parent:
        wide[4] += 36; narrow[0] += 1 # Foreign and self single-byte values occupy the identical footprint.
    narrow[2] = slot; result[key] = account_wire((code,wide,narrow))
    if profile != 'junior-panic' and value_key('P',42,digest(b'I')) not in parent:
        result[value_key('P',42,digest(b'I'))] = b'I'
        result[request_key(42,digest(b'I'),1)] = request_wire((slot,)) # Annulment preserves deferred provisions.
    key = chapter_service(255,99); code,wide,narrow = account_parse(parent[key],105)
    narrow=list(narrow);narrow[2]=slot;result[key]=account_wire((code,wide,narrow))
    (junior,_),(supervisor,_) = programs(profile)
    write = 2442+(3358+1023)//1024+(216+1023)//1024
    gas42=simulate(junior,gas_definitions(),prefix=[b'\0']*5)[0]+write+98+3983
    gas99=simulate(supervisor,gas_definitions(),prefix=[b'\0']*5)[0]+write+103*int(profile=='supervisor-checkpoint-panic')
    assert max(gas42,gas99)<=budget
    (current,previous,cores,services),_=statistics_parse(result[chapter_key(13)],statistics_config)
    activity={row[0]:list(row) for row in services}
    for sid,gas in ((42,gas42),(99,gas99)):
        row=activity.setdefault(sid,[sid]+[0]*11);row[9]+=1;row[11]+=gas # Annulled junior still contributes actual work/gas.
    result[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot,gas42=gas42,gas99=gas99,junior_annulled=profile in ('conflict','supervisor-checkpoint-panic'),value=value.hex(),provision_retained=profile!='junior-panic',yield_retained=own)


def expected_observations(check_frozen=True):
    """Calculate thirty full transitions with two report releases and parallel supervisor/junior conflict and annulment selection."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}; budgets = {}
        requests.append('C '+str(index+97)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in range(2, 8):
            budget = 100000
            gs = [pipeline.guarantee(parent, initial, core, slot, service=sid, accumulation_gas=budget) for core,sid in ((0,42),(1,99))] if slot in (3, 5) else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']; budgets[item['report'][:32]] = budget
            ass = assurances(parent, 5 if slot in (4, 6) else 0, 3)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (4, 6) else []
            plan = dict(available=released, processed=released, batches=[], ready=[[] for _ in range(12)], reports=reports, yielded=False)
            outputs = ((42, COMMITMENT),) if released and profile in ('supervisor-panic', 'stale-supervisor') else ()
            plan['foundation'] = foundation(parent, outputs)
            child, result = pipeline.advance(parent, initial, 'create', slot, gs, ass, plan=plan)
            if released:
                assert len(released) == 2
                traces[-1].append(effects(result, parent, profile, slot, budgets[released[0][:32]]))
            parent = result; encoded = checkpoint(list(parent.items()))
            requests.append('B '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        fixture = json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256'] == hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots'] == roots and fixture['successor_checkpoint_sha256'] == hashes
        assert fixture['traces'] == traces
    return requests, lines, dict(transitions=30, chains=5, roots=roots, checkpoint_sha256=hashes, traces=traces)
