# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map queued old-incarnation reports executed against current recreated service code cases."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-queued-incarnation.json'
PROFILES = ('stale','rebind','panic','checkpoint-panic','creator-panic')
PAYLOAD = b'R'


from state_privileges_oracle import wire as privileges_wire
from current_stf_supervised_storage_oracle import program as foreign_program


import current_stf_incarnation_authority_oracle as authority


def expected_observations(check_frozen=True):
    """Calculate35 full transitions preserving a genuinely queued old77 report across actual retirement/recreation."""
    requests,lines,roots,hashes,traces=[],[],[],[],[];pipeline=transfers.pipeline
    for index,profile in enumerate(PROFILES):
        parent=authority.original(profile);initial=dict(parent);reports={};events=[];old_report=None
        requests.append('C '+str(index+171));lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]);hashes.append([])
        for slot in range(2,9):
            targets=((0,99),(1,77)) if slot==3 else (((0,42),) if slot==4 else (((1,77),) if slot==6 else ()))
            gs=[pipeline.guarantee(parent,initial,core,slot,service=sid,accumulation_gas=100000) for core,sid in targets]
            for item in gs:
                reports[item['report'][:32]]=item['layout']
                if slot==3 and item['layout']['digests'][0][0]==77:
                    old_report=item['report'];assert item['layout']['digests'][0][1]==bytes(32) # This real queued report names the old empty77 code hash.
            bits=1 if slot==4 else (3 if slot==5 else 2)
            ass=assurances(parent,5 if slot in (4,5,7) else 0,bits)
            pending=pipeline.pending(parent[chapter_key(10)])
            released=[item['guarantee']['report'] for core,item in enumerate(pending) if item is not None and bits&(1<<core)] if slot in (4,5,7) else []
            plan=dict(available=released,processed=released,batches=[],ready=[[] for _ in range(12)],reports=reports,yielded=False)
            wire,result=pipeline.advance(parent,initial,'create',slot,gs,ass,plan=plan)
            if released:
                if slot==5:
                    assert old_report in released # Assurance releases the exact already-signed old report, with no rewritten code identity.
                event=authority.effects(result,parent,profile,slot,rebind_slot=5,write_slot=7)
                event['old_report_released']=slot==5;events.append(event)
            parent=result;encoded=checkpoint(list(parent.items()))
            requests.append('B '+body(gs,ass)[0].hex());lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
        assert old_report is not None
        traces.append(dict(profile=profile,old_report_sha256=hashlib.sha256(old_report).hexdigest(),old_code_hash=bytes(32).hex(),fixture_sha256=hashlib.sha256(authority.FIXTURE.read_bytes()).hexdigest(),events=events))
    if check_frozen:
        fixture=json.loads(FIXTURE.read_text());assert fixture['graypaper_commit']=='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256']==hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots']==roots and fixture['successor_checkpoint_sha256']==hashes
        assert fixture['traces']==json.loads(json.dumps(traces))
    return requests,lines,dict(transitions=35,chains=5,roots=roots,checkpoint_sha256=hashes,traces=traces)
