# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-population offender evidence, exact header markers and complete-map atomic refusals."""
from functools import cache
import copy
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_guests_oracle as guests
import jam_fuzzer_full_tickets_oracle as tickets
import jam_fuzzer_full_profile_oracle as full
from current_stf_oracle import Reader,checkpoint,tree
from state_layout_oracle import chapter_key,digest
from disputes_oracle import wire as disputes_wire
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-offenders.json'
GOOD,BAD = digest(b'full offender prior good report'),digest(b'full offender prior bad report')


def judgments(data):
    """Retain all four sorted unique judgment/offender sets, consuming every canonical byte."""
    reader = Reader(data);result = [[reader.take(32) for _ in range(reader.count())] for _ in range(4)];reader.done()
    assert all(group == sorted(set(group)) for group in result)
    return result


def encoded(groups):
    """Canonical set insertion deduplicates only state membership, never the header's evidence sequence."""
    return b''.join(natural(len(set(group)))+b''.join(sorted(set(group))) for group in groups)


@cache
def identities():
    """Known independent full-roster Ed25519 fixture identities bind evidence signatures without a native verifier."""
    return {row[32:64]:index for index,row in enumerate(guests.roster_records())}


def roster(data):
    """Preserve every opaque record for the selected full-size current/previous eligibility union."""
    reader = Reader(data);count = reader.count();assert 1 <= count <= 1023
    result = [reader.take(336) for _ in range(count)];reader.done()
    return result


def payload(*,culprits=(),faults=()):
    """Order each evidence section canonically while retaining a repeated key across the two sections."""
    return dict(verdicts=[],culprits=sorted(culprits,key=lambda row:row['key']),faults=sorted(faults,key=lambda row:row['key']))


def culprit(index,target=BAD):
    """A genuine guarantee-domain signature attributes the already-bad report to one full-roster member."""
    key,signature = guests.signed(index,b'jam_guarantee',target)
    return dict(target=target,key=key,signature=signature)


def fault(index,target=GOOD,valid=False):
    """Fault evidence signs the opposing judgment under its exact valid/invalid domain."""
    key,signature = guests.signed(index,b'jam_valid' if valid else b'jam_invalid',target)
    return dict(target=target,vote=valid,key=key,signature=signature)


def original(mode='create'):
    """Seed already-classified good/bad targets and an existing offender; later verdict admission is a separate family."""
    parent = guests.original(mode)
    parent[chapter_key(5)] = encoded(([GOOD],[BAD],[],[guests.roster_records()[7][32:64]]))
    return parent


def plan(parent,value,marker=None):
    """Independently check posterior evidence classification, prior eligibility, signatures and exact offender sequence."""
    assert not value['verdicts'] # This family's authority is evidence against supplied prior judgments, not new verdicts.
    groups = judgments(parent[chapter_key(5)])
    eligible = {row[32:64] for chapter in (8,9) for row in roster(parent[chapter_key(chapter)])}-set(groups[3])
    marks = []
    # All evidence uses the original eligibility set, allowing the same newly offending key in both sections.
    for section in ('culprits','faults'):
        entries = value[section]
        assert [row['key'] for row in entries] == sorted(set(row['key'] for row in entries)), 'InvalidKey'
        for row in entries:
            classification = 1 if section == 'culprits' or row['vote'] else 0
            assert row['target'] in groups[classification], 'InvalidEvidence'
            assert row['key'] in eligible, 'InvalidKey'
            domain = b'jam_guarantee' if section == 'culprits' else b'jam_valid' if row['vote'] else b'jam_invalid'
            index = identities()[row['key']]
            assert row['signature'] == guests.signed(index,domain,row['target'])[1], 'InvalidSignature'
            marks.append(row['key'])
    assert marker is None or marker == marks, 'InvalidMarker'
    groups[3].extend(marks)
    return encoded(groups),marks


def advance(parent,slot,value,*,marker=None):
    """Seal an authentic full-profile evidence body and calculate every posterior chapter before execution."""
    after,marks = plan(parent,value,marker)
    wire,entropy_output,author = tickets.sealed(parent,slot,[],disputes=disputes_wire(value),offenders=marks)
    body = b'\0'*4+disputes_wire(value);header = wire[:-len(body)]
    result = full.successor(parent,header,entropy_output,author=author);result[chapter_key(5)] = after
    return wire,result


def expected_observations(check_frozen=True):
    """Freeze high-ordinal evidence, repeated-section markers and exact invalid-key/signature/evidence/marker refusals."""
    parent = original();lines = ['P '+checkpoint(list(parent.items())).hex()];roots,hashes = [[]],[[]]
    value = payload(culprits=[culprit(0),culprit(1022)],faults=[fault(511),fault(1022,BAD,True)])
    _,marks = plan(parent,value);assert len(marks) == 4 and len(set(marks)) == 3
    damaged = copy.deepcopy(value);entry = damaged['culprits'][0];entry['signature'] = bytes([entry['signature'][0]^1])+entry['signature'][1:]
    controls = [(value,sorted(set(marks)),'InvalidMarker'),(damaged,None,'InvalidSignature'),
                (payload(culprits=[culprit(7)]),None,'InvalidKey'),(payload(culprits=[culprit(0,GOOD)]),None,'InvalidEvidence')]
    events = [(2,control,marker,reason) for control,marker,reason in controls]+[(2,value,None,None),
              (3,payload(culprits=[culprit(1022)]),None,'InvalidKey'),
              (3,payload(faults=[fault(510)]),None,None),(4,payload(),None,None)]
    for slot,incoming,marker,reason in events:
        if reason is not None:
            try: plan(parent,incoming,marker)
            except AssertionError as error: assert str(error) == reason
            else: raise AssertionError('independent reference admitted invalid offender evidence')
            # Wrong evidence is still honestly committed and sealed; only its required GP stage is invalid.
            honest = [row['key'] for section in ('culprits','faults') for row in incoming[section]]
            wire,_,_ = tickets.sealed(parent,slot,[],disputes=disputes_wire(incoming),offenders=honest if marker is None else marker)
            lines.append('R '+wire.hex()+' dispute/'+reason)
        else:
            wire,parent = advance(parent,slot,incoming);lines.append('B '+wire.hex())
        state = checkpoint(list(parent.items()));lines.append('O '+state.hex())
        roots[0].append(tree(list(parent.items()))[0].hex());hashes[0].append(hashlib.sha256(state).hexdigest())
    assert len(judgments(parent[chapter_key(5)])[3]) == 5
    evidence = dict(graypaper_commit=full.GP,chains=1,transitions=len(events),accepted=3,refused=5,
                    full_guests_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
