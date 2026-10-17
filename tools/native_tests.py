"""Launch code-only tests through the Hastur shipped with the pinned Nimony archive."""
from pathlib import Path
import json
import hashlib
import os
import platform
from setup_nimony import ROOT, cache_directory

# Preserve the existing cumulative suite identities while moving implementation assertions to native discovery.
UNIT_SUITES = ('natural', 'fixed_unsigned', 'bounded', 'composite', 'work_digest', 'ownership', 'report_snapshots', 'tickets', 'assurances', 'guarantees', 'disputes', 'work_package', 'header', 'block', 'block_private', 'bits', 'bits_private', 'collections', 'collections_private', 'c2', 'c2_private', 'state_layout', 'state_trie', 'state_trie_private', 'state_safrole', 'state_authorization', 'state_authorization_private', 'state_consensus', 'state_consensus_private', 'state_disputes', 'state_disputes_private')
# These cases keep numeric allocation evidence as well as native equality assertions.
ARC_SUITES = {'ownership': 'arc_release', 'report_snapshots': 'report_arc_release',
              'guarantees': 'guarantee_arc_release', 'disputes': 'dispute_arc_release',
              'work_package': 'package_arc_release', 'header': 'header_arc_release', 'block': 'block_arc_release',
              'bits': 'bits_arc_release', 'collections': 'collection_arc_release', 'c2': 'c2_arc_release', 'state_trie_private': 'trie_arc_release',
              'state_safrole': 'safrole_arc_release', 'state_authorization_private': 'authorization_arc_release',
              'state_consensus_private': 'consensus_arc_release', 'state_disputes_private': 'state_disputes_arc_release'}
UNIT_ROOT = ROOT/'tests/unit/codec'
STATE_ROOT = ROOT/'tests/unit/state'
# Preserve the production-only trie profile and observer-only refusal profiles in separate processes.
UNIT_LINKS = {'state_layout': 'observer', 'state_trie': 'crypto', 'state_trie_private': 'observer',
              'state_safrole': 'crypto', 'state_authorization': 'crypto', 'state_authorization_private': 'crypto',
              'state_consensus': 'crypto', 'state_consensus_private': 'crypto',
              'state_disputes': 'crypto', 'state_disputes_private': 'crypto'}
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


# Resolve a migrated suite without introducing a second copy or a fallback to its old native path.
def unit_source(name):
    if name not in UNIT_SUITES:
        # Unknown names belong to later migration chunks, never a silently omitted native case.
        raise ValueError('Unknown migrated unit suite: '+name)
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
    if name in UNIT_LINKS:
        # Never guess a library path or let a stale production library stand in for refusal instrumentation.
        profile = UNIT_LINKS[name]
        if libraries is None or profile not in libraries:
            # Linked application tests require an explicit result from pinned native preparation.
            raise ValueError('Missing native unit library profile: '+profile)
        library = Path(libraries[profile]).resolve()
        if not library.is_file():
            # Fail before Hastur can reuse any prior linked executable.
            raise FileNotFoundError('Missing native unit library: '+str(library))
        flags += ['--passC:-I'+str(ROOT/'native/crypto'), '--passL:'+str(library)]
    if platform.system() == 'Linux':
        # Keep the established Linux LTO linker rather than relying on the runner's defaults.
        flags.append('--passL:-fuse-ld=lld')
    # Isolated processes preserve each test's initialization/lifetime scope and keep generated drivers out of source.
    return [str(runner), '--bindir:'+str(compiler.parent),
            '--cachedir:'+str(cache_directory(compiler, ROOT/'build/nim-tests', 'unit-'+name if name in UNIT_LINKS else 'unit')),
            '--joined:off', *('--forward:'+flag for flag in flags), 'test', str(target)]


# Locate evidence beside compiler-isolated caches, without placing generated observations in source.
def unit_evidence_directory(compiler):
    return cache_directory(compiler, ROOT/'build/nim-tests', 'unit').parent/'evidence'


# Retire old observations before each native run so stale measurements cannot satisfy a new result.
def unit_environment(compiler, name=None, base=None):
    directory = unit_evidence_directory(compiler)
    directory.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ if base is None else base)
    for case in UNIT_SUITES if name is None else (name,):
        # Other suite observations may belong to another completed per-suite invocation.
        if case in ARC_SUITES:
            (directory/(case+'.json')).unlink(missing_ok=True)
        if case in UNIT_FIXTURES:
            # Refuse missing or changed fixture bytes before any native test can produce a success marker.
            variable, target, required = UNIT_FIXTURES[case]
            for path, expected in required:
                # A valid directory member cannot hide another missing or changed child input.
                if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    raise ValueError('Native unit fixture checksum mismatch: '+case+' '+path.name)
            environment[variable] = str(target)
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
