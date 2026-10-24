# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent raw-identity interchange across current-profile allowance and incarnation STF maps."""
import hashlib
import importlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers
from current_stf_oracle import checkpoint, decode_checkpoint, tree
from current_stf_effects_oracle import envelope
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key

FIXTURE=Path(__file__).parent/'fixtures/current-stf-interchange.json'
FAMILIES=('bless_allowances','allowance_revocation','allowance_eligibility','incarnation_authority','foreign_creation','foreign_transfers','queued_incarnation')


def declarations(state, original, child):
    """Enumerate authored raw identities, proving exact key coverage without reversing physical hashes or using native output."""
    lines=['ragnarok-current-logical-source-v1'];covered={chapter_key(i) for i in range(1,17)}
    for sid in (42,99,77):
        metadata=chapter_service(255,sid)
        if metadata not in state:
            continue # The fixed reserved child is absent until genuine selected creation.
        covered.add(metadata);lines.append('s='+str(sid))
        if sid==77:
            storage=[];preimages=[];requests=[]
            if child is not None:
                preimages=[digest(child)];requests=[(digest(child),len(child))] # Only the independently authored replacement code can inhabit this child.
        else:
            payload=b'abc' if sid==42 else b'M';code=account(original[metadata],105)[0]
            code_key=value_key('P',sid,code)
            # Missing-code controls have the same known Halt program as the transfer baseline.
            raw=original.get(code_key)
            if raw is None:
                baseline=transfers.original('halt');raw=baseline[value_key('P',sid,account(baseline[metadata],105)[0])]
                assert digest(raw)==code
            storage=[b'',b'\1\2' if sid==42 else b'\5',b'\7']
            preimages=[digest(b''),digest(payload),code]
            requests=[(digest(b''),0),(digest(payload),len(payload)),(code,len(raw)),(digest(b'I' if sid==42 else b'Q'),1)]
        for raw in storage:
            key=value_key('S',sid,raw)
            if key in state:
                covered.add(key);lines.append('k='+raw.hex()) # Empty raw keys remain explicit even when values are empty.
        for hashed in preimages:
            key=value_key('P',sid,hashed)
            if key in state:
                covered.add(key);lines.append('p='+hashed.hex()) # Presence is taken from the independently calculated full successor.
        for hashed,length in requests:
            key=request_key(sid,hashed,length)
            if key in state:
                covered.add(key);lines.append('r='+hashed.hex()+':'+str(length)) # A pending request needs no fabricated preimage.
    assert covered==set(state), (covered-set(state),set(state)-covered)
    return ('\n'.join(lines)+'\n').encode()


def expected_observations(check_frozen=True):
    """Freeze complete maps plus independent identity ASCII before native export, reload and actual-source startup."""
    requests=[];lines=[];roots=[];hashes=[];traces=[]
    for family in FAMILIES:
        source=importlib.import_module('current_stf_'+family+'_oracle');commands,expected,evidence=source.expected_observations()
        requests.extend(line+' exchange' if line.startswith('C ') else line for line in commands)
        initial=None;ordinal=-1;child=None
        for line in expected:
            if line.startswith('P '):
                initial=decode_checkpoint(bytes.fromhex(line[2:]));ordinal+=1;child=None
                if family in ('incarnation_authority','queued_incarnation'):
                    import current_stf_incarnation_authority_oracle as authority
                    child=envelope(*authority.programs(source.PROFILES[ordinal])[2])
                elif family=='foreign_creation':
                    child=source.replacement() # Literal child code is authored by the existing independent creation reference.
            if line.startswith('O '):
                state=decode_checkpoint(bytes.fromhex(line[2:]));text=declarations(state,initial,child)
                lines.append('L '+text.hex())
            lines.append(line)
        roots.extend(evidence['roots']);hashes.extend(evidence['checkpoint_sha256'])
        traces.append(dict(family=family,fixture_sha256=hashlib.sha256(source.FIXTURE.read_bytes()).hexdigest(),transitions=evidence['transitions']))
    if check_frozen:
        frozen=json.loads(FIXTURE.read_text());assert frozen['successor_roots']==roots and frozen['successor_checkpoint_sha256']==hashes and frozen['traces']==traces
    return requests,lines,dict(transitions=sum(t['transitions'] for t in traces),chains=len(roots),roots=roots,checkpoint_sha256=hashes,traces=traces)
