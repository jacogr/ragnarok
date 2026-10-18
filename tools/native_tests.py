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
from verification_inventory import UNIT_SUITES, ARC_SUITES, UNIT_LINKS
UNIT_ROOT = ROOT/'tests/unit/codec'
STATE_ROOT = ROOT/'tests/unit/state'
CRYPTO_ROOT = ROOT/'tests/unit/crypto'
QUIC_ROOT = ROOT/'tests/unit/quic'
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
    if name in ('crypto_seeds', 'assurance_context', 'guarantee_message', 'signing_domains', 'bandersnatch_owners'):
        return CRYPTO_ROOT/('test_'+name+'.nim')
    return (STATE_ROOT if name in UNIT_LINKS else UNIT_ROOT)/('test_'+name+'.nim')


# Bound independent test workers explicitly; callers can request serial controls without changing semantics.
def unit_jobs():
    raw = os.environ.get('COMPILE_CHECK_JOBS', '4')
    if raw not in ('1', '2', '3', '4'):
        # Reject auto/unbounded values rather than unexpectedly oversubscribing a CI runner.
        raise ValueError('COMPILE_CHECK_JOBS must be an integer from 1 to 4')
    return int(raw)


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
        profiles = ('bandersnatch_observer', 'bandersnatch', profile) if name in ('validator_state', 'ticket_admission', 'ticket_state', 'sealer_state') else ('bandersnatch_observer', profile) if name == 'bandersnatch_owners' else (profile,)
        for key in profiles:
            # The Rust owner observer and production primitive remain separate unchanged libraries.
            if key not in libraries:
                raise ValueError('Missing native unit library profile: '+key)
            library = Path(libraries[key]).resolve()
            if not library.is_file():
                # Fail before Hastur can reuse any prior linked executable.
                raise FileNotFoundError('Missing native unit library: '+str(library))
            flags.append('--passL:'+str(library))
            if key in ('bandersnatch', 'bandersnatch_observer') or profile == 'quic':
                # Locate the maintained Rust ABI and observer on both supported hosts.
                flags.append('--passL:-Wl,-rpath,'+str(library.parent))
        include = 'bandersnatch' if name == 'bandersnatch_owners' else 'quic' if profile == 'quic' else 'crypto'
        flags.append('--passC:-I'+str(ROOT/'native'/include))
        if name in ('validator_state', 'ticket_admission', 'ticket_state', 'sealer_state'):
            # Keep both native headers available without changing production ABI declarations.
            flags.append('--passC:-I'+str(ROOT/'native/bandersnatch'))
            for function in ('setup_new', 'setup_free', 'ring_verify' if name in ('ticket_admission', 'ticket_state', 'sealer_state') else 'commit'):
                # Only this refusal profile observes setup/commit calls; real native release still runs.
                flags.append('--passC:-Dbs_'+function+'=bo_'+function)
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
    # Working-directory-specific caches cannot reuse older prebuilds with paths relative to the repository root.
    # Isolated processes preserve each test's initialization/lifetime scope and keep generated drivers out of source.
    return [str(runner), '--bindir:'+str(compiler.parent),
            '--cachedir:'+str(cache_directory(compiler, ROOT/'build/tests/native', 'working-unit-'+name if name in UNIT_LINKS else 'working-unit')),
            '--jobs:'+str(unit_jobs() if name is None else 1),
            '--joined:off', *('--forward:'+flag for flag in flags), 'test', str(target)]


# Hastur's scheduling history uses a relative path even with --cachedir; contain it under build.
def unit_work_directory(compiler):
    directory = cache_directory(compiler, ROOT/'build/tests/native', 'unit').parent/'work'
    directory.mkdir(parents=True, exist_ok=True)
    return directory


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
        if case in ('quic_transport', 'quic_integration', 'state_store_replay', 'authorization_transition', 'history_transition', 'signing_domains', 'entropy_transition', 'validator_rotation', 'validator_state', 'ticket_admission', 'ticket_state', 'sealer_schedule', 'sealer_state', 'safrole_markers', 'marker_state') and case not in manifest:
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


# Prepare published storage bytes once per invocation; native assertions own all store verdicts.
def unit_store_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from state_store_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_STORE_REPLAY', path, ((path, evidence['fixture_sha256']),))
    return {'state_store_replay': fixture}, evidence


# Admission fixtures contain upstream proof/accumulator values, not a Python implementation of selection.
def unit_ticket_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from ticket_admission_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_TICKET_ADMISSION', path, ((path, evidence['fixture_sha256']),))
    return {'ticket_admission': fixture, 'ticket_state': fixture}, evidence


# Only trusted upstream fields are transported; the native suite executes every schedule equation.
def unit_sealer_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from sealer_schedule_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_SEALER_SCHEDULE', path, ((path, evidence['fixture_sha256']),))
    from safrole_marker_fixtures import prepare as prepare_markers
    marker_path, marker_evidence = prepare_markers(folder)
    marker_fixture = ('RAGNAROK_SAFROLE_MARKERS', marker_path, ((marker_path, marker_evidence['fixture_sha256']),))
    evidence['markers'] = marker_evidence
    return {'sealer_schedule': fixture, 'sealer_state': fixture, 'safrole_markers': marker_fixture, 'marker_state': marker_fixture}, evidence


# Prepare exact published roster projections for the bounded planner's native assertions.
def unit_validator_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from validator_rotation_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_VALIDATOR_STF', path, ((path, evidence['fixture_sha256']),))
    return {'validator_rotation': fixture, 'validator_state': fixture}, evidence


# Prepare only the published entropy/time projections, keeping full Safrole execution outside this suite.
def unit_entropy_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from entropy_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_ENTROPY_STF', path, ((path, evidence['fixture_sha256']),))
    return {'entropy_transition': fixture}, evidence


# Prepare public upstream credentials with independent OpenSSL positive/old-domain verdicts.
def unit_signing_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from signing_domain_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_SIGNING_DOMAINS', path, ((path, evidence['fixture_sha256']),))
    return {'signing_domains': fixture}, evidence


# Prepare published history cases and independent output-tree commitments for native assertions.
def unit_history_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from history_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_HISTORY_STF', path, ((path, evidence['fixture_sha256']),))
    return {'history_transition': fixture}, evidence


# Prepare complete pinned authorization STF cases; the native suite executes and asserts the subsystem.
def unit_authorization_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from authorization_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_AUTHORIZATION_STF', path, ((path, evidence['fixture_sha256']),))
    return {'authorization_transition': fixture}, evidence


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
    store_fixtures, store_evidence = unit_store_fixture(folder)
    fixtures.update(store_fixtures)
    (folder/'store-preparation.json').write_text(json.dumps(store_evidence, indent=2)+'\n')
    authorization_fixtures, authorization_evidence = unit_authorization_fixture(folder)
    fixtures.update(authorization_fixtures)
    (folder/'authorization-preparation.json').write_text(json.dumps(authorization_evidence, indent=2)+'\n')
    history_fixtures, history_evidence = unit_history_fixture(folder)
    fixtures.update(history_fixtures)
    (folder/'history-preparation.json').write_text(json.dumps(history_evidence, indent=2)+'\n')
    signing_fixtures, signing_evidence = unit_signing_fixture(folder)
    fixtures.update(signing_fixtures)
    (folder/'signing-preparation.json').write_text(json.dumps(signing_evidence, indent=2)+'\n')
    entropy_fixtures, entropy_evidence = unit_entropy_fixture(folder)
    fixtures.update(entropy_fixtures)
    (folder/'entropy-preparation.json').write_text(json.dumps(entropy_evidence, indent=2)+'\n')
    validator_fixtures, validator_evidence = unit_validator_fixture(folder)
    ticket_fixtures, ticket_evidence = unit_ticket_fixture(folder)
    (folder/'ticket-preparation.json').write_text(json.dumps(ticket_evidence, indent=2)+'\n')
    fixtures.update(validator_fixtures)
    fixtures.update(ticket_fixtures)
    sealer_fixtures, sealer_evidence = unit_sealer_fixture(folder)
    fixtures.update(sealer_fixtures)
    (folder/'sealer-preparation.json').write_text(json.dumps(sealer_evidence, indent=2)+'\n')
    (folder/'validator-preparation.json').write_text(json.dumps(validator_evidence, indent=2)+'\n')
    # All fixture hashes are verified and old observations retired before any native suite runs.
    selected = unit_environment(compiler, base=selected, fixtures=fixtures)
    for arguments in unit_plan(compiler, libraries):
        # Every failed compile, assertion or output mismatch must stop the invocation.
        print('+ '+' '.join(arguments), flush=True)
        subprocess.run(arguments, cwd=unit_work_directory(compiler), env=selected, check=True)
    for name in ARC_SUITES:
        # Preserve measured live occupancy rather than baking host heap sizes into goldens.
        print('ARC '+name+': '+json.dumps(unit_evidence(compiler, name), sort_keys=True), flush=True)


# Imports expose profiles without provisioning dependencies or running tests.
if __name__ == '__main__':
    main()
