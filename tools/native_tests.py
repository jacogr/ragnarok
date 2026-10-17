"""Launch native application tests through the Hastur shipped with the pinned Nimony archive."""
from pathlib import Path
import json
import hashlib
import os
import subprocess
import sys
import platform
from setup_nimony import ROOT, cache_directory

# Preserve the existing cumulative suite identities while moving implementation assertions to native discovery.
UNIT_SUITES = ('natural', 'fixed_unsigned', 'bounded', 'composite', 'work_digest', 'ownership', 'report_snapshots', 'tickets', 'assurances', 'guarantees', 'disputes', 'work_package', 'header', 'block', 'block_private', 'bits', 'bits_private', 'collections', 'collections_private', 'c2', 'c2_private', 'state_layout', 'state_trie', 'state_trie_private', 'state_safrole', 'state_authorization', 'state_authorization_private', 'state_consensus', 'state_consensus_private', 'state_disputes', 'state_disputes_private', 'state_history', 'state_history_private', 'state_availability', 'state_availability_private', 'state_workqueues', 'state_workqueues_private', 'state_privileges', 'state_privileges_private', 'state_statistics', 'state_statistics_private', 'state_outputs', 'state_outputs_private', 'state_accounts', 'state_accounts_private', 'state_service_values', 'service_values_private', 'state_requests', 'state_requests_private', 'state_composition_private', 'crypto_seeds', 'assurance_context', 'guarantee_message', 'bandersnatch_owners', 'quic_io', 'quic_transport', 'quic_protocol', 'quic_integration', 'quic_integration_disabled')
# These cases keep numeric allocation evidence as well as native equality assertions.
ARC_SUITES = {'ownership': 'arc_release', 'report_snapshots': 'report_arc_release', 'guarantees': 'guarantee_arc_release', 'disputes': 'dispute_arc_release', 'work_package': 'package_arc_release', 'header': 'header_arc_release', 'block': 'block_arc_release', 'bits': 'bits_arc_release', 'collections': 'collection_arc_release', 'c2': 'c2_arc_release', 'state_trie_private': 'trie_arc_release', 'state_safrole': 'safrole_arc_release', 'state_authorization_private': 'authorization_arc_release', 'state_consensus_private': 'consensus_arc_release', 'state_disputes_private': 'state_disputes_arc_release', 'state_history_private': 'history_arc_release', 'state_availability_private': 'availability_arc_release', 'state_workqueues_private': 'workqueues_arc_release', 'state_privileges_private': 'privileges_arc_release', 'state_statistics_private': 'statistics_arc_release', 'state_outputs_private': 'outputs_arc_release', 'state_accounts_private': 'accounts_arc_release', 'service_values_private': 'service_values_arc_release', 'state_requests_private': 'requests_arc_release', 'state_composition_private': 'composition_arc_release', 'crypto_seeds': 'crypto_arc_release', 'assurance_context': 'assurance_context_arc_release', 'guarantee_message': 'guarantee_message_arc_release', 'bandersnatch_owners': 'bandersnatch_arc_release', 'quic_io': 'quic_io_arc_release', 'quic_integration': 'integration_arc_release'}
UNIT_ROOT = ROOT/'tests/unit/codec'
STATE_ROOT = ROOT/'tests/unit/state'
CRYPTO_ROOT = ROOT/'tests/unit/crypto'
QUIC_ROOT = ROOT/'tests/unit/quic'
# Preserve the production-only trie profile and observer-only refusal profiles in separate processes.
UNIT_LINKS = {'state_layout': 'observer', 'state_trie': 'crypto', 'state_trie_private': 'observer', 'state_safrole': 'crypto', 'state_authorization': 'crypto', 'state_authorization_private': 'crypto', 'state_consensus': 'crypto', 'state_consensus_private': 'crypto', 'state_disputes': 'crypto', 'state_disputes_private': 'crypto', 'state_history': 'crypto', 'state_history_private': 'crypto', 'state_availability': 'crypto', 'state_availability_private': 'crypto', 'state_workqueues': 'crypto', 'state_workqueues_private': 'crypto', 'state_privileges': 'crypto', 'state_privileges_private': 'crypto', 'state_statistics': 'crypto', 'state_statistics_private': 'crypto', 'state_outputs': 'crypto', 'state_outputs_private': 'crypto', 'state_accounts': 'crypto', 'state_accounts_private': 'crypto', 'state_service_values': 'crypto', 'service_values_private': 'observer', 'state_requests': 'crypto', 'state_requests_private': 'observer', 'state_composition_private': 'observer', 'crypto_seeds': 'observer', 'assurance_context': 'observer', 'guarantee_message': 'observer', 'bandersnatch_owners': 'bandersnatch', 'quic_io': None, 'quic_transport': 'quic', 'quic_protocol': 'quic', 'quic_integration': 'observer', 'quic_integration_disabled': None}
# Fixture targets may be files or directories; each entry lists every byte source that must match its pin.
GUARANTEE_FIXTURE = ROOT/'tests/fixtures/guarantee-report.bin'
BLOCK_FIXTURES = ROOT/'tests/fixtures/block-tiny'
UNIT_FIXTURES = {
    'guarantees': ('RAGNAROK_GUARANTEE_FIXTURE', GUARANTEE_FIXTURE, (
        (GUARANTEE_FIXTURE, '8f13efdbca5aa7c5158c7cc62c71e5a9ed6ab2e22032d46946f4a304c55688fc'),)),
    'block': ('RAGNAROK_BLOCK_FIXTURES', BLOCK_FIXTURES, (
        (BLOCK_FIXTURES/'tickets.bin', '69d59e7ec8933d92a202d7a439b05f5f69ae3c0a4bf00bc08bf68dcaa256bde3'),
        (BLOCK_FIXTURES/'preimages.bin', '874f3bed57dab9927170d5344b8489ad0662d5ee0c22a58ca25a362415cc8c90'),
        (BLOCK_FIXTURES/'guarantees.bin', '4e5b4574b56bf0f0f974db8f4486fd14219f9d5f5a95c4743100bf5ed75ec690'),
        (BLOCK_FIXTURES/'assurances.bin', '5438827a87cfd20f1eaccd8d20858a69af88df2459172a37e6aa9d9639c506e3'),
        (BLOCK_FIXTURES/'disputes.bin', '83e526e84c919fb1efb020bee185c9f63c3692e004d13820546473ed59e31b21'),
        (BLOCK_FIXTURES/'header.bin', 'c4f4658a9c04bca5d249c7ca5f14845bd012311213f6bb24076dcdddbb268fa2'),
    )),
}

# Shared independent report bytes retain availability and queued-report fixture identity.
STATE_REPORT = ROOT/'tests/fixtures/state-report.bin'
for case in ('state_availability', 'state_availability_private', 'state_workqueues', 'state_workqueues_private'):
    # Every consumer verifies the same exact source bytes before its native assertions execute.
    UNIT_FIXTURES[case] = ('RAGNAROK_STATE_REPORT', STATE_REPORT, ((STATE_REPORT, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371'),))

# Composition receives the same sixteen independently authored chapter values as the original trial.
COMPOSITION_FIXTURE = ROOT/'tests/fixtures/composition-chapters.txt'
UNIT_FIXTURES['state_composition_private'] = ('RAGNAROK_COMPOSITION_FIXTURE', COMPOSITION_FIXTURE,
    ((COMPOSITION_FIXTURE, '3d45577099002c493cb7dc6fa4b3ee2f7ebfa389952a0c4cae3c7c382db7265b'),))


# Resolve a migrated suite without introducing a second copy or a fallback to its old native path.
def unit_source(name):
    if name not in UNIT_SUITES:
        # Unknown names belong to later migration chunks, never a silently omitted native case.
        raise ValueError('Unknown migrated unit suite: '+name)
    if name.startswith('quic_'):
        # Transport lifecycle and disabled integration retain their own native suite directory.
        return QUIC_ROOT/('test_'+name+'.nim')
    # Crypto ownership cases share the runner without being mistaken for state serialization tests.
    if name in ('crypto_seeds', 'assurance_context', 'guarantee_message', 'bandersnatch_owners'):
        return CRYPTO_ROOT/('test_'+name+'.nim')
    return (STATE_ROOT if name in UNIT_LINKS else UNIT_ROOT)/('test_'+name+'.nim')


# Assemble a native runner invocation; Python supplies paths/flags, never test assertions or verdict parsing.
def unit_command(compiler, name=None, libraries=None):
    compiler = Path(compiler).resolve()
    runner = compiler.parent/'hastur'
    if not runner.is_file():
        # Never substitute a global runner from a different compiler revision.
        raise FileNotFoundError('Pinned Nimony archive has no Hastur: '+str(runner))
    target = UNIT_ROOT if name is None else unit_source(name)
    sources = sorted(target.glob('*.nim')) if target.is_dir() else [target]
    if not sources:
        # Hastur accepts an empty directory; the project must not report zero tests as a successful suite.
        raise ValueError('Native unit suite is empty: '+str(target))
    for source in sources:
        # Each positive test owns an explicit expected-output file; missing evidence must fail before compilation.
        if not source.is_file() or not source.with_suffix('.output').is_file():
            raise FileNotFoundError('Missing native test or expected output: '+str(source))
    flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundchecks:on',
             '--passC:-flto', '--passL:-flto']
    if name in UNIT_LINKS and UNIT_LINKS[name] is not None:
        # Never guess a library path or let a stale production library stand in for refusal instrumentation.
        profile = UNIT_LINKS[name]
        if libraries is None or profile not in libraries:
            # Linked application tests require an explicit result from pinned native preparation.
            raise ValueError('Missing native unit library profile: '+profile)
        profiles = ('bandersnatch_observer', profile) if name == 'bandersnatch_owners' else (profile,)
        for key in profiles:
            # The Rust owner observer and production primitive remain separate unchanged libraries.
            if key not in libraries:
                raise ValueError('Missing native unit library profile: '+key)
            library = Path(libraries[key]).resolve()
            if not library.is_file():
                # Fail before Hastur can reuse any prior linked executable.
                raise FileNotFoundError('Missing native unit library: '+str(library))
            flags.append('--passL:'+str(library))
            if name == 'bandersnatch_owners' or profile == 'quic':
                # Locate the maintained Rust ABI and observer on both supported hosts.
                flags.append('--passL:-Wl,-rpath,'+str(library.parent))
        include = 'bandersnatch' if name == 'bandersnatch_owners' else 'quic' if profile == 'quic' else 'crypto'
        flags.append('--passC:-I'+str(ROOT/'native'/include))
        if name == 'bandersnatch_owners':
            # Rename only these test call sites, exactly as in the existing owner-observation profile.
            for function in ('key_new', 'key_free', 'setup_new', 'setup_free'):
                flags.append('--passC:-Dbs_'+function+'=bo_'+function)
    if name == 'quic_integration':
        # Exercise the enabled provider separately from its default typed-refusal profile.
        flags.append('-d:integration')
    if platform.system() == 'Linux':
        # Keep the established Linux LTO linker rather than relying on the runner's defaults.
        flags.append('--passL:-fuse-ld=lld')
    # Isolated processes preserve each test's initialization/lifetime scope and keep generated drivers out of source.
    return [str(runner), '--bindir:'+str(compiler.parent),
            '--cachedir:'+str(cache_directory(compiler, ROOT/'build/tests/native', 'unit-'+name if name in UNIT_LINKS else 'unit')),
            '--joined:off', *('--forward:'+flag for flag in flags), 'test', str(target)]


# Locate evidence beside compiler-isolated caches, without placing generated observations in source.
def unit_evidence_directory(compiler):
    return cache_directory(compiler, ROOT/'build/tests/native', 'unit').parent/'evidence'


# Retire old observations before each native run so stale measurements cannot satisfy a new result.
def unit_environment(compiler, name=None, base=None, fixtures=None):
    directory = unit_evidence_directory(compiler)
    directory.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ if base is None else base)
    manifest = {**UNIT_FIXTURES, **(fixtures or {})}
    for case in UNIT_SUITES if name is None else (name,):
        # Other suite observations may belong to another completed per-suite invocation.
        if case in ARC_SUITES:
            (directory/(case+'.json')).unlink(missing_ok=True)
        if case in ('quic_transport', 'quic_integration') and case not in manifest:
            # Inherited paths cannot replace newly prepared native transport/integration fixtures.
            raise ValueError('Missing prepared native unit fixtures: '+case)
        if case in manifest:
            # Refuse missing or changed fixture bytes before any native test can produce a success marker.
            variable, target, required = manifest[case]
            for path, expected in required:
                # A valid directory member cannot hide another missing or changed child input.
                if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    raise ValueError('Native unit fixture checksum mismatch: '+case+' '+path.name)
            environment.update({key: str(value) for key, value in target.items()} if variable is None
                               else {variable: str(target)})
    return {**environment, 'RAGNAROK_TEST_EVIDENCE': str(directory)}


# Preserve the historical numeric report fields, rejecting absent or malformed observations.
def unit_evidence(compiler, name):
    observed = json.loads((unit_evidence_directory(compiler)/(name+'.json')).read_text())
    required = {'cycles', 'occupied_before', 'occupied_after'} | ({'schemas'} if name == 'ownership' else set())
    if not isinstance(observed, dict) or set(observed) != required or any(type(value) is not int or value < 0 for value in observed.values()):
        # Numeric evidence is not an arbitrary success flag or an unchecked JSON object.
        raise ValueError('Invalid native ARC observation: '+name)
    if observed['cycles'] != 1000 or observed['occupied_before'] != observed['occupied_after']:
        # This report consistency check retains the prior safeguard; the code assertion runs inside Nim too.
        raise ValueError('Native ARC workload did not return to baseline: '+name)
    if name == 'ownership' and observed['schemas'] != 5:
        # A smaller schema workload cannot stand in for the original five-owner regression.
        raise ValueError('Incomplete native ARC schema workload')
    return observed


# Flatten fixture groups into the exact input files consumed and hashed by cumulative verification.
def unit_fixture_sources():
    return [path for _, _, required in UNIT_FIXTURES.values() for path, _ in required]


# Describe freshly generated certificates and independent CE fixtures without committing private keys.
def unit_runtime_fixtures(certificates, original, reload):
    transport = {'RAGNAROK_TEST_CERT': certificates/'a.cert.pem',
                 'RAGNAROK_TEST_KEY': certificates/'a.key.pem'}
    integration = {'RAGNAROK_TEST_WIRES': original, 'RAGNAROK_TEST_RELOAD': reload}
    # Every referenced input is hashed and rechecked before the native process, including later siblings.
    cert_files = tuple((path, hashlib.sha256(path.read_bytes()).hexdigest()) for path in transport.values())
    wires = tuple((folder/(str(index)+'.bin'), hashlib.sha256((folder/(str(index)+'.bin')).read_bytes()).hexdigest())
                  for folder in (original, reload) for index in range(8))
    return {'quic_transport': (None, transport, cert_files), 'quic_integration': (None, integration, wires)}


# Group only dependency-free codecs; linked, networking and resource profiles remain separate.
def unit_batches():
    pure = tuple(name for name in UNIT_SUITES if name not in UNIT_LINKS)
    actual = set(UNIT_ROOT.glob('*.nim'))
    if actual != {unit_source(name) for name in pure}:
        # Extra/missing directory members cannot silently change the group covered by one verdict.
        raise ValueError('Native codec discovery differs from the suite registry')
    return [('codec', pure, None)]+[(name, (name,), name) for name in UNIT_LINKS]


# Discover pure codecs once and link each remaining suite with its required native profile.
def unit_plan(compiler, libraries):
    return [unit_command(compiler, target, libraries) for _, _, target in unit_batches()]


# Prepare pinned native fixtures and run every ordinary suite with strict output/ARC evidence.
def main():
    from setup_nimony import installed
    compiler, _ = installed()
    selected = dict(os.environ)
    # Reuse the same pristine pinned crypto, Rust and QUIC preparations as CI.
    sys.path.insert(0, str(ROOT/'tests'))
    from nimony_crypto import prepare
    folder = ROOT/'build/tests/native/preparation'
    folder.mkdir(parents=True, exist_ok=True)
    crypto, observer, evidence = prepare(folder)
    (folder/'preparation.json').write_text(json.dumps(evidence, indent=2)+'\n')
    libraries = dict(crypto=crypto, observer=observer)
    from bandersnatch_native import prepare as prepare_bandersnatch
    bs, bs_observer, bs_evidence = prepare_bandersnatch(folder)
    libraries.update(bandersnatch=bs, bandersnatch_observer=bs_observer)
    (folder/'bandersnatch-preparation.json').write_text(json.dumps(bs_evidence, indent=2)+'\n')
    from nimony_quic import prepare as prepare_quic
    quic, certificates, quic_evidence = prepare_quic()
    libraries['quic'] = quic
    (folder/'quic-preparation.json').write_text(json.dumps(quic_evidence, indent=2)+'\n')
    import test_integration as integration_fixture
    integration_fixture.BUILD.mkdir(parents=True, exist_ok=True)
    wires, _ = integration_fixture.corpus()
    reload = folder/'integration-reload'
    reload.mkdir(exist_ok=True)
    for index in range(8):
        # Different candidate bytes expose a refused bank reload that accidentally publishes partial data.
        wire = bytearray((wires/(str(index)+'.bin')).read_bytes())
        wire[0] ^= 128
        (reload/(str(index)+'.bin')).write_bytes(wire)
    fixtures = unit_runtime_fixtures(certificates, wires, reload)
    # All fixture hashes are verified and old observations retired before any native suite runs.
    selected = unit_environment(compiler, base=selected, fixtures=fixtures)
    for arguments in unit_plan(compiler, libraries):
        # Every failed compile, assertion or output mismatch must stop the invocation.
        print('+ '+' '.join(arguments), flush=True)
        subprocess.run(arguments, cwd=ROOT, env=selected, check=True)
    for name in ARC_SUITES:
        # Preserve measured live occupancy rather than baking host heap sizes into goldens.
        print('ARC '+name+': '+json.dumps(unit_evidence(compiler, name), sort_keys=True), flush=True)


# Imports expose profiles without provisioning dependencies or running tests.
if __name__ == '__main__':
    main()
