#!/usr/bin/env python3
"""Build the pinned historical JAM Bandersnatch Rust ABI and check both native-language adapters."""
import argparse
import concurrent.futures
import ctypes
import hashlib
import json
from pathlib import Path
import platform
import random
import subprocess
import urllib.request
from test_quic import fetch_source, run
from toolchain_checks import odin_matches

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/bandersnatch'
PINS = json.loads((ROOT / 'spec/bandersnatch-pins.json').read_text())
FIXTURES = ROOT / 'vectors/official/bandersnatch'


# Check fixed source identities, public SRS and the whole registry dependency lock before executing any build.
def sources(fetch):
    assert PINS['source_patches'] == []
    # Only the compatible historical backend/spec are required; newer suites are research comparisons.
    for name, entry in PINS['sources'].items():
        destination = BUILD / 'sources' / name
        marker = destination / '.ragnarok-source.json'
        # Fetch missing immutable archives, never apply patches or run fetched install scripts.
        if fetch and not marker.exists():
            fetch_source({'repository':entry['repository'],'commit':entry['commit']}, destination)
        assert marker.exists(), f'Use --fetch for {name}'
        recorded = json.loads(marker.read_text())
        assert recorded['repository']==entry['repository'] and recorded['commit']==entry['commit']
        digest=hashlib.sha256()
        # Verify all pristine source bytes, not just a mutable cache marker; no compiler output belongs here.
        for path in sorted(destination.rglob('*')):
            # The local provenance marker is checked separately; only upstream file contents define the tree.
            if path.is_file() and path.name!='.ragnarok-source.json':
                digest.update(path.relative_to(destination).as_posix().encode()+b'\0'+hashlib.sha256(path.read_bytes()).digest())
        assert digest.hexdigest()==entry['tree_sha256'], f'Modified dependency source: {name}' 
    assert hashlib.sha256((BUILD / 'sources/spec-jam' / PINS['srs']['path']).read_bytes()).hexdigest()==PINS['srs']['sha256']
    assert hashlib.sha256((ROOT / 'native/bandersnatch/Cargo.lock').read_bytes()).hexdigest()==PINS['cargo_lock_sha256']
    # Committed fixtures include public spec vectors and reduced independent official JAM cases.
    for filename, expected in PINS['fixture_files'].items():
        assert hashlib.sha256((ROOT / filename).read_bytes()).hexdigest()==expected


# Check reduced official fixtures against the complete immutable upstream JSON, without copying full STF states into Git.
def official_sources(fetch):
    entry=PINS['official_jam']
    cache=BUILD/'official'
    cache.mkdir(exist_ok=True)
    # Each reduced fixture retains only cryptographic inputs and independent expected outputs/roots.
    for local,remote in entry['files'].items():
        original=cache/Path(local).name
        # Only explicit fetch mode obtains a missing original; cached originals remain hash checked.
        if fetch and not original.exists():
            url=f"https://raw.githubusercontent.com/{entry['repository']}/{entry['commit']}/{remote}"
            original.write_bytes(urllib.request.urlopen(url,timeout=60).read())
        assert original.exists(), 'Use --fetch to obtain official source fixtures'
        assert hashlib.sha256(original.read_bytes()).hexdigest()==entry['source_sha256'][local]
        v=json.loads(original.read_text());reduced=json.loads((ROOT/local).read_text())
        # Epoch-change padding checks the posterior pending ring rather than tickets from the prior epoch.
        if 'padding' in local:
            expected={'capacity':len(v['post_state']['gamma_k']),'root':v['post_state']['gamma_z'],
                      'members':[k['bandersnatch'] for k in v['post_state']['gamma_k']]}
        else:
            # These selected official cases start with an empty accumulator and accept every submitted ordered ticket.
            assert 'ok' in v['output'] and not v['pre_state']['gamma_a']
            tickets=[]
            assert len(v['input']['extrinsic'])==len(v['post_state']['gamma_a'])
            for ticket,score in zip(v['input']['extrinsic'],v['post_state']['gamma_a']):
                assert ticket['attempt']==score['attempt']
                tickets.append({**ticket,'output':score['id']})
            expected={'capacity':len(v['pre_state']['gamma_k']),'entropy':v['pre_state']['eta'][2],
                      'root':v['pre_state']['gamma_z'],'members':[k['bandersnatch'] for k in v['pre_state']['gamma_k']],
                      'tickets':tickets}
        assert expected==reduced, local


# Build the reviewed locked Cargo closure and both checked debug/release wrappers against exactly one Rust library.
def build(fetch):
    assert subprocess.check_output(['rustc','--version'],text=True).startswith('rustc '+PINS['rust']+' ')
    assert subprocess.check_output(['cargo','--version'],text=True).startswith('cargo '+PINS['rust']+' ')
    assert PINS['nim'] in subprocess.check_output(['nim','--version'],text=True)
    assert odin_matches(subprocess.check_output(['odin','version'],text=True),PINS['odin'])
    manifest = ROOT / 'native/bandersnatch/Cargo.toml'
    system = platform.system()
    assert system in ('Darwin','Linux')
    library = BUILD / 'target/release' / ('libragnarok_bandersnatch.dylib' if system=='Darwin' else 'libragnarok_bandersnatch.so')
    # Only --fetch allows registry downloads; build/tests subsequently run locked and offline.
    with (BUILD / 'build.log').open('w') as log:
        if fetch:
            run(['cargo','fetch','--locked','--manifest-path',manifest],log)
        features = subprocess.check_output(['cargo','tree','--locked','--offline','--manifest-path',str(manifest),'-e','features'],text=True)
        assert 'test-vectors' not in features, 'Unsafe deterministic/non-ZK ring features must never build'
        assert 'secret-split' in features
        (BUILD / 'cargo-features.log').write_text(features)
        run(['cargo','fmt','--manifest-path',manifest,'--','--check'],log)
        run(['cargo','test','--locked','--offline','--manifest-path',manifest,'--target-dir',BUILD / 'target'],log)
        run(['cargo','build','--release','--locked','--offline','--manifest-path',manifest,'--target-dir',BUILD / 'target'],log)
        linker = [f'-extra-linker-flags:-Wl,-rpath,{library.parent}']
        # Odin's macOS linker needs the selected SDK; the Linux toolchain uses system defaults.
        if system=='Darwin':
            sdk = subprocess.check_output(['xcrun','--show-sdk-path'],text=True).strip()
            linker = [f'-extra-linker-flags:-isysroot {sdk} -Wl,-rpath,{library.parent}']
        # Do not disable union/variant checks in either optimized build.
        for mode in ('debug','release'):
            run(['nim','c','--mm:arc','--cc:clang','--skipParentCfg','--skipUserCfg',
                 *(['-d:release'] if mode=='release' else []),f'--passL:{library}',f'--passL:-Wl,-rpath,{library.parent}',
                 f'--nimcache:{BUILD / ("nim-cache-"+mode)}',f'--out:{BUILD / ("nim-"+mode)}',
                 ROOT / 'nim/bandersnatch/driver.nim'],log)
            run(['odin','build',ROOT / 'odin/bandersnatch_driver','-vet','-strict-style',
                 *(['-o:speed'] if mode=='release' else []),f'-out:{BUILD / ("odin-"+mode)}',*linker],log)


# Query one trusted fixture process with bounded public arguments; no secret material is logged by the runner.
def query(binary, command, *values):
    args = [v.hex() or '-' if isinstance(v,bytes) else str(v) for v in values]
    return subprocess.check_output([str(binary),command,*args],text=True,timeout=30).strip()


# Decode public fixture hex without retaining any source buffer reference.
def octets(value):
    return bytes.fromhex(value.removeprefix('0x'))


# Assemble the normative historical output/Pedersen/membership encoding directly from published proof fields.
def ring_proof(v):
    return b''.join(octets(v[k]) for k in ['gamma','proof_pk_com','proof_r','proof_ok','proof_s','proof_sb','ring_proof'])


# Reject an invalid result and ensure the malformed-input path is not a caught backend panic.
def rejected(value):
    assert value.startswith('error:') and value!='error:7', value


# Verify public vectors, owned lifetimes, context separation and independent official tiny/full JAM tickets.
def suite(binary):
    assert query(binary,'O')=='ok'
    assert query(binary,'T')=='ok'
    failed = subprocess.run([str(binary),'F'],capture_output=True,text=True)
    diagnostic = failed.stdout+failed.stderr
    assert failed.returncode!=0
    assert ('FieldDefect' in diagnostic if binary.name.startswith('nim') else 'assert' in diagnostic.lower())
    ietf = json.loads((FIXTURES / 'ietf.json').read_text())
    rings = json.loads((FIXTURES / 'ring.json').read_text())
    # Ordinary contextual signatures must reproduce every published field exactly, not just verify themselves.
    for v in ietf:
        sk,pk,context,ad = [octets(v[k]) for k in ('sk','pk','alpha','ad')]
        expected = octets(v['gamma'])+octets(v['proof_c'])+octets(v['proof_s'])
        assert query(binary,'P',sk)==pk.hex()
        assert query(binary,'S',sk,context,ad)==expected.hex()
        assert query(binary,'V',pk,expected,context,ad)==v['beta'][:64]
        rejected(query(binary,'V',pk,expected,context+b'!',ad))
        rejected(query(binary,'V',pk,expected,context,ad+b'!'))
    # Ring roots/proofs come from the published trusted-SRS vectors; generation uses the safe randomized backend feature set.
    for v in rings:
        proof = ring_proof(v)
        assert len(proof)==784 and len(octets(v['ring_pks_com']))==144
        assert query(binary,'R',8,octets(v['ring_pks']))==v['ring_pks_com']
        assert query(binary,'W',8,octets(v['ring_pks_com']),proof,octets(v['alpha']),octets(v['ad']))==v['beta'][:64]
    official = 0
    # JAM domains/serialization are constructed here in native test policy, not hidden in Rust.
    for profile in ('tiny','full'):
        v = json.loads((FIXTURES / f'jam-{profile}.json').read_text())
        members = b''.join(octets(k) for k in v['members'])
        assert query(binary,'R',v['capacity'],members)==v['root'][2:]
        # Each independently generated ticket's extracted output must equal its official post-state score.
        for ticket in v['tickets']:
            context = b'jam_ticket_seal'+octets(v['entropy'])+bytes([ticket['attempt']])
            actual = query(binary,'W',v['capacity'],octets(v['root']),octets(ticket['signature']),context,b'')
            assert actual==ticket['output'][2:]
            official += 1
    padded_jam = json.loads((FIXTURES / 'jam-padding.json').read_text())
    assert query(binary,'R',padded_jam['capacity'],b''.join(octets(k) for k in padded_jam['members']))==padded_jam['root'][2:]
    v = rings[0]
    root,proof,members = octets(v['ring_pks_com']),ring_proof(v),octets(v['ring_pks'])
    rejected(query(binary,'W',8,root,proof,b'wrong-context',b''))
    rejected(query(binary,'W',8,root,proof,b'',b'wrong-additional'))
    rejected(query(binary,'W',8,root[:-1],proof,b'',b''))
    rejected(query(binary,'W',8,root,proof[:-1],b'',b''))
    # Membership proving cannot silently truncate rings or wrap/select an unrelated key index.
    rejected(query(binary,'G',8,octets(v['sk']),-1,members,b'',b''))
    rejected(query(binary,'G',8,octets(v['sk']),8,members,b'',b''))
    rejected(query(binary,'G',8,octets(v['sk']),0,members,b'',b''))
    rejected(query(binary,'R',1,members))
    rejected(query(binary,'R',8,members[:-1]))
    # Invalid encoded members are replaced by the specified padding point independently by both wrappers.
    padding = bytes.fromhex('92ca79e61dd90c1573a8693f199bf6e1e86835cc715cdcf93f5ef222560023aa')
    altered = bytes([255])*32+members[32:]
    padded = padding+members[32:]
    assert query(binary,'R',8,altered)==query(binary,'R',8,padded)
    assert query(binary,'P',bytes(32)).startswith('error:')
    # Width/encoding guards must not expose a default key or proof.
    for n in (0,1,31,33):
        rejected(query(binary,'P',bytes(n)))
        rejected(query(binary,'V',bytes(n),bytes(96),b'',b''))
    return {'ietf_vectors':len(ietf),'ring_vectors':len(rings),'official_jam_tickets':official,
            'ownership':'passed','native_threads':4,'rounds_per_thread':32,'checked_failure':'passed'}


# Cross-check proof creation and output/context binding with the two language owners over the same backend.
def cross():
    nim,odin = BUILD / 'nim-release', BUILD / 'odin-release'
    v = json.loads((FIXTURES / 'ring.json').read_text())[0]
    members,sk,root = octets(v['ring_pks']),octets(v['sk']),octets(v['ring_pks_com'])
    # A safe fresh ring proof need not equal non-ZK deterministic publication vectors.
    for prover,verifier in ((nim,odin),(odin,nim)):
        proof = octets(query(prover,'G',8,sk,3,members,b'',b''))
        assert len(proof)==784
        assert query(verifier,'W',8,root,proof,b'',b'')==v['beta'][:64]
    # Extra deterministic scalars are canonical little endian test material, not production entropy.
    for i in range(1,17):
        scalar = i.to_bytes(32,'little');context = bytes(range(i));ad = b'additional'
        public = query(nim,'P',scalar)
        assert public==query(odin,'P',scalar)
        signature = query(nim,'S',scalar,context,ad)
        assert signature==query(odin,'S',scalar,context,ad)
        assert query(nim,'V',octets(public),octets(signature),context,ad)==query(odin,'V',octets(public),octets(signature),context,ad)
    return {'ring_proofs':2,'ietf_messages':16}


# Exercise exact widths, malformed points/scalars/roots and all-or-nothing writes at the Rust/C boundary.
def bridge_checks():
    library = BUILD / 'target/release' / ('libragnarok_bandersnatch.dylib' if platform.system()=='Darwin' else 'libragnarok_bandersnatch.so')
    lib = ctypes.CDLL(str(library));p = ctypes.c_void_p;s = ctypes.c_size_t
    lib.bs_verify.argtypes=[p,p,s,p,s,p,s,p];lib.bs_verify.restype=ctypes.c_uint32
    lib.bs_setup_new.argtypes=[s,ctypes.POINTER(p)];lib.bs_setup_new.restype=ctypes.c_uint32
    lib.bs_setup_free.argtypes=[p];lib.bs_setup_free.restype=None
    lib.bs_ring_verify.argtypes=[p,p,p,s,p,s,p,s,p];lib.bs_ring_verify.restype=ctypes.c_uint32
    lib.bs_key_new.argtypes=[p,s,ctypes.POINTER(p)];lib.bs_key_new.restype=ctypes.c_uint32
    holder = p(0x1234)
    assert lib.bs_key_new(None,32,ctypes.byref(holder))==1 and holder.value==0x1234
    output = (ctypes.c_ubyte*32)(*[0xa5]*32)
    # Every wrong ordinary/ring proof length must fail before reading any claimed proof bytes.
    for width in range(100):
        # The sole valid width is exercised by the independent known-answer suites.
        if width!=96:
            assert lib.bs_verify(None,None,width,None,0,None,0,output)==1
    for width in range(786):
        # All other anonymous proof widths fail before borrowing the purported proof.
        if width!=784:
            assert lib.bs_ring_verify(None,None,None,width,None,0,None,0,output)==1
    assert bytes(output)==bytes([0xa5])*32
    owner=p();assert lib.bs_setup_new(8,ctypes.byref(owner))==0
    v = json.loads((FIXTURES / 'ring.json').read_text())[0];proof = ring_proof(v);root = octets(v['ring_pks_com'])
    rng = random.Random(784)
    # Mutated fixed encodings must reject normally, without unwinding across FFI or publishing a hash.
    for _ in range(64):
        mutated = bytearray(proof);index = rng.randrange(len(mutated));mutated[index]^=1<<rng.randrange(8)
        status = lib.bs_ring_verify(owner,root,bytes(mutated),784,None,0,None,0,output)
        assert status not in (0,6),status
        assert bytes(output)==bytes([0xa5])*32
    assert lib.bs_ring_verify(owner,root,proof,784,None,65537,None,0,output)==1
    lib.bs_setup_free(owner)
    return {'ordinary_wrong_widths':99,'ring_wrong_widths':785,'mutated_ring_proofs':64}


# Require positive imports before testing important nominal-role and private-owner compilation failures.
def types():
    pairs = [('var a: BsPublicKey; let b: BsOutput = a','a:bs.Bs_Public_Key;b:bs.Bs_Output=a;_=b'),
             ('var a: BsKey; let b: BsSetup = a','a:bs.Bs_Key;b:bs.Bs_Setup=a;_=b'),
             ('var a: BsKey; discard a.state','a:bs.Bs_Key;_=a.state')]
    positive_nim=BUILD/'positive.nim';positive_nim.write_text('import "../../nim/bandersnatch/bandersnatch"\nvar a:BsPublicKey\ndiscard a\n')
    subprocess.run(['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',str(positive_nim)],check=True,capture_output=True)
    positive_odin=BUILD/'positive.odin';positive_odin.write_text('package main\nimport bs "../../odin/bandersnatch"\nmain::proc(){a:bs.Bs_Public_Key;_=a}\n')
    subprocess.run(['odin','check',str(positive_odin),'-file'],check=True,capture_output=True)
    # Diagnostics must show intended role/field errors, never invalid import paths or module names.
    with (BUILD/'type-checks.log').open('wb') as log:
        for index,(nim,odin) in enumerate(pairs):
            np=BUILD/f'negative_{index}.nim';np.write_text('import "../../nim/bandersnatch/bandersnatch"\n'+nim+'\n')
            result=subprocess.run(['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',str(np)],capture_output=True);log.write(result.stdout+result.stderr)
            assert result.returncode!=0 and b'invalid module name' not in result.stderr
            op=BUILD/f'negative_{index}.odin';op.write_text('package main\nimport bs "../../odin/bandersnatch"\nmain::proc(){'+odin+'}\n')
            result=subprocess.run(['odin','check',str(op),'-file'],capture_output=True);log.write(result.stdout+result.stderr)
            assert result.returncode!=0 and b'Invalid import path' not in result.stderr


# Produce a success summary only after source pins, Rust tests, ABI guards and all native suites pass.
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--fetch',action='store_true');args=parser.parse_args()
    BUILD.mkdir(parents=True,exist_ok=True);(BUILD/'results.json').unlink(missing_ok=True)
    sources(args.fetch);official_sources(args.fetch);build(args.fetch);types()
    names=['nim-debug','odin-debug','nim-release','odin-release']
    # Suites have independent processes/owners, so parallel fixture checks do not race destruction.
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        records=dict(zip(names,pool.map(suite,[BUILD/name for name in names])))
    summary={'status':'passed','platform':platform.platform(),'suite':PINS['suite'],'suites':records,
             'cross_language':cross(),'abi_checks':bridge_checks(),'negative_type_probes':6,'source_patches':[]}
    (BUILD/'results.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))


# Importing helpers never performs source downloads or native builds.
if __name__=='__main__':
    main()
