"""Launch code-only tests through the Hastur shipped with the pinned Nimony archive."""
from pathlib import Path
import json
import os
import platform
from setup_nimony import ROOT, cache_directory

# Preserve the existing cumulative suite identities while moving implementation assertions to native discovery.
UNIT_SUITES = ('natural', 'fixed_unsigned', 'bounded', 'composite', 'work_digest', 'ownership', 'report_snapshots')
# These cases keep numeric allocation evidence as well as native equality assertions.
ARC_SUITES = {'ownership': 'arc_release', 'report_snapshots': 'report_arc_release'}
UNIT_ROOT = ROOT/'tests/unit/codec'


# Resolve a migrated suite without introducing a second copy or a fallback to its old native path.
def unit_source(name):
    if name not in UNIT_SUITES:
        # Unknown names belong to later migration chunks, never a silently omitted native case.
        raise ValueError('Unknown migrated unit suite: '+name)
    return UNIT_ROOT/('test_'+name+'.nim')


# Assemble a native runner invocation; Python supplies paths/flags, never test assertions or verdict parsing.
def unit_command(compiler, name=None):
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
    if platform.system() == 'Linux':
        # Keep the established Linux LTO linker rather than relying on the runner's defaults.
        flags.append('--passL:-fuse-ld=lld')
    # Isolated processes preserve each test's initialization/lifetime scope and keep generated drivers out of source.
    return [str(runner), '--bindir:'+str(compiler.parent),
            '--cachedir:'+str(cache_directory(compiler, ROOT/'build/nim-tests', 'unit')),
            '--joined:off', *('--forward:'+flag for flag in flags), 'test', str(target)]


# Locate evidence beside compiler-isolated caches, without placing generated observations in source.
def unit_evidence_directory(compiler):
    return cache_directory(compiler, ROOT/'build/nim-tests', 'unit').parent/'evidence'


# Retire old observations before each native run so stale measurements cannot satisfy a new result.
def unit_environment(compiler, name=None, base=None):
    directory = unit_evidence_directory(compiler)
    directory.mkdir(parents=True, exist_ok=True)
    for case in UNIT_SUITES if name is None else (name,):
        # Other suite observations may belong to another completed per-suite invocation.
        if case in ARC_SUITES:
            (directory/(case+'.json')).unlink(missing_ok=True)
    return {**(os.environ if base is None else base), 'RAGNAROK_TEST_EVIDENCE': str(directory)}


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
