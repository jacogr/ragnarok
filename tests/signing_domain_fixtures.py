"""Provenance-checked upstream credentials verify token bytes independently of project-generated signatures."""
import hashlib
import json
import subprocess
from report_oracle import ROOT, encode, from_json


# Verify immutable external signatures with OpenSSL under both proposed domain spellings.
def external_verify(folder, key, signature, message):
    (folder/'public.der').write_bytes(bytes.fromhex('302a300506032b6570032100')+key)
    (folder/'signature.bin').write_bytes(signature)
    verdicts = []
    for candidate in (message, b'$'+message):
        # A dollar-prefixed transcript must fail with the same published key/signature pair.
        (folder/'message.bin').write_bytes(candidate)
        result = subprocess.run(['openssl', 'pkeyutl', '-verify', '-rawin', '-pubin', '-keyform', 'DER',
            '-inkey', str(folder/'public.der'), '-sigfile', str(folder/'signature.bin'),
            '-in', str(folder/'message.bin')], capture_output=True, timeout=20)
        verdicts.append(result.returncode)
    assert verdicts == [0, 1], ('published credential domain verdicts', verdicts)


# Validate exact pinned Git blobs before transporting public credentials and independently reconstructed messages.
def prepare(folder):
    folder.mkdir(parents=True, exist_ok=True)
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    lines, sources = [], []
    for family, name in (('assurances', 'some_assurances'), ('reports', 'report_curr_rotation')):
        for profile in ('tiny', 'full'):
            # These successful cases include real upstream signatures and their selected current validator keys.
            path = f'stf/{family}/{profile}/{name}-1.json'
            raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+path])
            digest = hashlib.sha256(raw).hexdigest()
            assert digest == pins['git_blobs'][path]
            case = json.loads(raw)
            assert 'ok' in case['output']
            validators = case['pre_state']['curr_validators']
            cores = 2 if profile == 'tiny' else 341
            checked = 0
            if family == 'assurances':
                # Preserve every assurance and the complete validator-index key mapping, not just one sample key.
                assurances = case['input']['assurances']
                parent = case['input']['parent'][2:]
                keys = ''.join(value['ed25519'][2:] for value in validators)
                lines.append(f'A {cores} {len(validators)} {parent} {keys} {len(assurances)}')
                for index, value in enumerate(assurances):
                    assert value['anchor'][2:] == parent
                    bits = bytes.fromhex(value['bitfield'][2:])
                    assert len(bits) == (cores+7)//8
                    message = b'jam_available'+hashlib.blake2b(bytes.fromhex(parent)+bits, digest_size=32).digest()
                    key = bytes.fromhex(validators[value['validator_index']]['ed25519'][2:])
                    signature = bytes.fromhex(value['signature'][2:])
                    if index in (0, len(assurances)-1):
                        # Independent provider samples bracket each profile; native verification checks every credential.
                        external_verify(folder, key, signature, message)
                    lines.append(f'{value["validator_index"]} {bits.hex()} {signature.hex()} {message.hex()}')
                    checked += 1
            else:
                # Reports use the independent existing C.2 encoder; signature success also binds every encoded field.
                guarantees = case['input']['guarantees']
                assert len(guarantees) == 1
                guarantee = guarantees[0]
                assert not guarantee['report']['segment_root_lookup'] # This chosen family's report has no lookup pairs.
                report = encode(from_json(guarantee['report']))
                message = b'jam_guarantee'+hashlib.blake2b(report, digest_size=32).digest()
                lines.append(f'G {report.hex()} {len(guarantee["signatures"])}')
                for index, value in enumerate(guarantee['signatures']):
                    key = bytes.fromhex(validators[value['validator_index']]['ed25519'][2:])
                    signature = bytes.fromhex(value['signature'][2:])
                    if index in (0, len(guarantee['signatures'])-1):
                        # Both report-profile endpoints also reject the old domain independently.
                        external_verify(folder, key, signature, message)
                    lines.append(f'{key.hex()} {signature.hex()} {message.hex()}')
                    checked += 1
            sources.append(dict(path=path, sha256=digest, credentials=checked))
    path = folder/'signing-domains.txt'
    path.write_text('\n'.join(lines)+'\n')
    evidence = dict(cases=len(sources), openssl_credentials=8, credentials=sum(s['credentials'] for s in sources), sources=sources,
        vector_commit=pins['commit'], fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        provider=subprocess.check_output(['openssl', 'version'], text=True).strip())
    (folder/'signing-domains.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
