"""Independent header.tex commitment answers and pinned full-block inputs; no native verification."""
import copy
import hashlib
import json
import subprocess
from test_support import ROOT
from test_codec import reference_encode as natural
from block_oracle import child_wires
from header_oracle import from_json as header_json, wire as header_wire
from report_oracle import from_json as report_json, encode as report_wire


# The fixed five-family sequence carries no outer variable-length discriminator.
def commitment(value, cores):
    parts = child_wires(value, cores)
    digest = lambda data: hashlib.blake2b(data, digest_size=32).digest()
    parts[1] = natural(len(value['preimages']))+b''.join(
        x['requester'].to_bytes(4, 'little')+digest(bytes.fromhex(x['blob'][2:])) for x in value['preimages'])
    parts[2] = natural(len(value['guarantees']))+b''.join(
        digest(report_wire(report_json(x['report'])))+x['slot'].to_bytes(4, 'little')+
        natural(len(x['signatures']))+b''.join(s['validator_index'].to_bytes(2, 'little')+
        bytes.fromhex(s['signature'][2:]) for s in x['signatures']) for x in value['guarantees'])
    return digest(b''.join(digest(part) for part in parts)), sum(map(len, parts))


# Preserve original source integrity before constructing independent mathematical test transports.
def prepare(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    rows, sources = [], []
    source = 'vendor/jamtestvectors/codec/full/extrinsic.json'
    raw = (ROOT/source).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == pins['files'][source]
    full = json.loads(raw)
    sources.append(dict(path=source, sha256=pins['files'][source]))
    empty = dict(tickets=[], preimages=[], guarantees=[], assurances=[],
                 disputes=dict(verdicts=[], culprits=[], faults=[]))
    ordered = copy.deepcopy(full)
    ordered['disputes']['verdicts'].sort(key=lambda verdict: verdict['target']) # Explicit authored counterpart to the known policy-invalid codec sample.
    examples = [('empty', empty), ('published-rejected-order', full), ('authored-rich-from-codec', ordered)]
    images = copy.deepcopy(empty)
    images['preimages'] = [dict(requester=i, blob='0x') for i in range(129)]
    examples.append(('129-empty-preimages', images))
    # Each transformed or direct family must contribute to the same fixed ordering independently.
    for family in ('tickets', 'preimages', 'guarantees', 'assurances', 'disputes'):
        changed = copy.deepcopy(ordered)
        if family == 'tickets':
            changed[family][0]['signature'] = changed[family][0]['signature'][:-2]+'ab'
        elif family == 'preimages':
            changed[family][0]['blob'] += 'ab'
        elif family == 'guarantees':
            changed[family][0]['report']['authorizer_hash'] = '0x'+'ab'*32
        elif family == 'assurances':
            changed[family][0]['signature'] = changed[family][0]['signature'][:-2]+'ab'
        else:
            changed[family]['faults'][0]['signature'] = changed[family]['faults'][0]['signature'][:-2]+'ab'
        examples.append(('changed-'+family, changed))
    for name, value in examples:
        expected, projected = commitment(value, 341)
        rows.append(' '.join([name, b''.join(child_wires(value, 341)).hex(), expected.hex(),
                             str(projected), str(6+len(value['preimages'])+len(value['guarantees']))]))
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'extrinsic-commitment.txt'
    path.write_text('\n'.join(rows)+'\n')
    evidence = dict(cases=len(rows), sources=sources, vector_commit=pins['commit'],
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'extrinsic-commitment.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence


# Real full-state maps anchor root checks; posterior fields remain expected outputs, not stage inputs.
def prepare_admission(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    rows, sources = [], []
    chapters = (4, 6, 8, 9, 11)
    from state_layout_oracle import chapter_key
    for family in ('fallback', 'safrole'):
        for number in (12, 13, 25, 49, 100):
            cases = []
            for ordinal in (number-1, number):
                path = f'traces/{family}/{ordinal:08}.json'
                raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+path])
                digest = hashlib.sha256(raw).hexdigest()
                assert digest == pins['git_blobs'][path]
                cases.append(json.loads(raw))
                sources.append(dict(path=path, sha256=digest))
            prior, case = cases
            block = case['block']
            header = header_wire('H', header_json(block['header']))
            parent = header_wire('H', header_json(prior['block']['header']))
            assert hashlib.blake2b(parent, digest_size=32).hexdigest() == block['header']['parent'][2:]
            expected, _ = commitment(block['extrinsic'], 2)
            assert expected.hex() == block['header']['extrinsic_hash'][2:]
            before = case['pre_state']
            assert before['state_root'] == block['header']['parent_state_root']
            after = {bytes.fromhex(x['key'][2:]): bytes.fromhex(x['value'][2:]) for x in case['post_state']['keyvals']}
            entries = ','.join(x['key'][2:]+'='+x['value'][2:] for x in before['keyvals'])
            rows.append(' '.join([family+'/'+str(number), (header+b''.join(child_wires(block['extrinsic'], 2))).hex(),
                parent.hex(), entries, *(after[chapter_key(c)].hex() for c in chapters),
                after[chapter_key(5)].hex(), before['state_root'][2:]]))
    assert len(rows) == 10
    path = folder/'block-admission.txt'
    path.write_text('\n'.join(rows)+'\n')
    evidence = dict(cases=10, sources=sources, vector_commit=pins['commit'],
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'block-admission.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
