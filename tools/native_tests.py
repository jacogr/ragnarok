# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Launch native application tests through the Hastur shipped with the pinned Nimony archive.

Exposes native suite planning, compiler commands, environments and evidence paths; main runs the
standalone native test launcher, optionally selecting one discovered suite with bounded log output.
"""
from pathlib import Path
from contextlib import contextmanager
import fcntl
import json
import hashlib
import os
import subprocess
import platform
import argparse
from setup_nimony import ROOT, cache_directory

# Share directory-discovered suite identities with selection, cumulative reports and provenance.
from verification_inventory import UNIT_SOURCES, UNIT_SUITES, ARC_SUITES
from native_requirements import NATIVE_REQUIREMENTS, UNIT_LINKS
from native_fixture_contracts import FIXTURE_CONTRACTS
# Keep the runtime-fixture helper available to existing launcher consumers.
from native_fixtures import unit_runtime_fixtures
UNIT_ROOT = ROOT/'tests/unit/codec'


# Resolve static dependencies declared by this suite; fixture identities are discovered beside data.
def unit_static_fixtures(name):
    """Return all checked-in contracts requested by one discovered native suite."""
    return tuple(FIXTURE_CONTRACTS[identity]
                 for identity in NATIVE_REQUIREMENTS[name].get('fixtures', []))


# Resolve a discovered suite directly from its source path, independently of linking metadata.
def unit_source(name):
    if name not in UNIT_SUITES:
        # Unknown selections fail before native preparation rather than silently running no tests.
        raise ValueError('Unknown native unit suite: '+name)
    return UNIT_SOURCES[name]


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
        requirements = NATIVE_REQUIREMENTS[name]
        profiles = requirements['libraries']
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
        for include in requirements['includes']:
            # Headers retain their explicit order after the ordered native library arguments.
            flags.append('--passC:-I'+str(ROOT/'native'/include))
        for function in requirements['observers']:
            # Rename only declared test call sites; production libraries remain unchanged.
            flags.append('--passC:-Dbs_'+function+'=bo_'+function)
    for define in NATIVE_REQUIREMENTS[name]['defines'] if name is not None else ():
        # Integration remains an explicit per-suite opt-in, independent of library preparation.
        flags.append('-d:'+define)
    if platform.system() == 'Linux':
        # Keep the established Linux LTO linker rather than relying on the runner's defaults.
        flags.append('--passL:-fuse-ld=lld')
    # Serial suites with identical build inputs can reuse semantic intermediates; each main still
    # compiles and runs separately. Separate profiles protect observer renames, defines and native ABIs.
    inputs = []
    if name in UNIT_LINKS:
        # Rebuilt foreign code or edited headers must invalidate even an otherwise identical profile.
        requirements = NATIVE_REQUIREMENTS[name]
        inputs = [Path(libraries[key]).resolve() for key in requirements['libraries']]
        for include in requirements['includes']:
            # Header discovery follows the same maintained include directories used by the compiler.
            inputs.extend(sorted((ROOT/'native'/include).glob('*.h')))
    profile = dict(directory=str(target.parent if name is not None else target), flags=flags,
                   native={str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})
    identity = hashlib.sha256(json.dumps(profile, sort_keys=True).encode()).hexdigest()[:16]
    # The parallel codec pool keeps its own cache; it cannot race with serial profile reuse.
    cache_name = 'working-codec' if name is None else 'working-profile-'+identity
    return [str(runner), '--bindir:'+str(compiler.parent),
            '--cachedir:'+str(cache_directory(compiler, ROOT/'build/tests/native', cache_name)),
            '--jobs:'+str(unit_jobs() if name is None else 1),
            '--joined:off', *('--forward:'+flag for flag in flags), 'test', str(target)]


# Hastur's scheduling history uses a relative path even with --cachedir; contain it under build.
def unit_work_directory(compiler):
    directory = cache_directory(compiler, ROOT/'build/tests/native', 'unit').parent/'work'
    directory.mkdir(parents=True, exist_ok=True)
    return directory


# Serialize access to compiler-owned intermediates and ARC observations across local invocations.
@contextmanager
def unit_cache_lock(compiler):
    path = cache_directory(compiler, ROOT/'build/tests/native', 'unit').parent/'run.lock'
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a') as lock:
        # The supported Linux/macOS hosts release this advisory lock even if a process is killed.
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            # Failed compilation, assertion or evidence validation cannot strand the next invocation.
            fcntl.flock(lock, fcntl.LOCK_UN)


# Locate evidence beside compiler-isolated caches, without placing generated observations in source.
def unit_evidence_directory(compiler):
    return cache_directory(compiler, ROOT/'build/tests/native', 'unit').parent/'evidence'


# Retire old observations before each native run so stale measurements cannot satisfy a new result.
def unit_environment(compiler, name=None, base=None, fixtures=None, suites=None):
    directory = unit_evidence_directory(compiler)
    directory.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ if base is None else base)
    manifest = fixtures or {}
    selected = tuple(suites) if suites is not None else UNIT_SUITES if name is None else (name,)
    if (not set(selected) <= set(UNIT_SUITES) or len(selected) != len(set(selected))
            or (name is not None and selected != (name,))):
        # A batch cannot retire or prepare evidence for an unknown, duplicate or conflicting selection.
        raise ValueError('Invalid native unit environment scope')
    for case in selected:
        # Other suite observations may belong to another completed per-suite invocation.
        if case in ARC_SUITES:
            (directory/(case+'.json')).unlink(missing_ok=True)
        if NATIVE_REQUIREMENTS[case]['prepared'] and case not in manifest:
            # Inherited paths cannot replace newly prepared native transport/integration fixtures.
            raise ValueError('Missing prepared native unit fixtures: '+case)
        contracts = unit_static_fixtures(case)
        if case in manifest:
            # Generated providers keep their existing scope, checksum and environment contracts.
            contracts += (manifest[case],)
        for variable, target, required in contracts:
            # Refuse missing or changed fixture bytes before any native test can produce a success marker.
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
    return sorted({path for _, _, required in FIXTURE_CONTRACTS.values() for path, _ in required})


# Group only dependency-free codecs; linked, networking and resource profiles remain separate.
def unit_batches():
    pure = tuple(name for name in UNIT_SUITES if name not in UNIT_LINKS)
    actual = set(UNIT_ROOT.glob('*.nim'))
    if actual != {unit_source(name) for name in pure}:
        # Extra/missing directory members cannot silently change the group covered by one verdict.
        raise ValueError('Native codec directory changed after suite discovery')
    return [('codec', pure, None)]+[(name, (name,), name) for name in UNIT_LINKS]


# Partition discovered batches without registering suite names or compiling any test twice.
def unit_partition(shard=None):
    batches = unit_batches()
    if shard is None:
        # Local verification remains complete unless a caller explicitly selects a CI partition.
        return batches, True
    if (not isinstance(shard, (tuple, list)) or len(shard) != 2
            or any(type(value) is not int for value in shard)
            or not 1 <= shard[0] <= shard[1] <= 8):
        # Invalid or empty partition declarations must fail before setup or verdict calculation.
        raise ValueError('Unit shard must be index/count with 1 <= index <= count <= 8')
    index, count = shard
    # Spread serial linked/resource workloads lexically; codec discovery and corpora each run once.
    selected = ([batches[0]] if index == 1 else []) + batches[index::count]
    return selected, index == count


# Parse the same bounded partition notation used by the CI matrix and retained report metadata.
def parse_unit_shard(value):
    shard = tuple(int(part) for part in value.split('/'))
    unit_partition(shard)
    return shard


# Discover pure codecs once and link each remaining suite with its required native profile.
def unit_plan(compiler, libraries):
    return [unit_command(compiler, target, libraries) for _, _, target in unit_batches()]


# Execute only the selected scope, retaining its own fixture checks, exit status and fresh ARC evidence.
def run_units(compiler, libraries, fixtures, suite=None):
    with unit_cache_lock(compiler):
        # Evidence retirement, execution and validation share the compiler cache's exclusive lifetime.
        _run_units(compiler, libraries, fixtures, suite)


# Execute an already-locked standalone selection without changing suite or evidence ownership.
def _run_units(compiler, libraries, fixtures, suite):
    if suite is None:
        # Complete native verification retains the established batching, environment and streamed diagnostics.
        selected = unit_environment(compiler, fixtures=fixtures)
        for arguments in unit_plan(compiler, libraries):
            # A failed compile, assertion or expected-output comparison must terminate the complete run.
            print('+ '+' '.join(arguments), flush=True)
            subprocess.run(arguments, cwd=unit_work_directory(compiler), env=selected, check=True)
        observed = ARC_SUITES
    else:
        # A focused run must neither execute another suite nor retire another suite's ARC observation.
        arguments = unit_command(compiler, suite, libraries)
        selected = unit_environment(compiler, name=suite, fixtures=fixtures)
        log = ROOT/'build/tests/native/selected'/(suite+'.log')
        log.parent.mkdir(parents=True, exist_ok=True)
        try:
            # Keep successful compiler output out of agent context without weakening Hastur's verdict.
            with log.open('w') as output:
                subprocess.run(arguments, cwd=unit_work_directory(compiler), env=selected,
                               stdout=output, stderr=subprocess.STDOUT, check=True)
        except subprocess.CalledProcessError:
            # Failures expose a bounded excerpt and retain the full diagnostic file for investigation.
            print('FAIL '+suite+'; log: '+str(log), flush=True)
            print('\n'.join(log.read_text(errors='replace').splitlines()[-40:]), flush=True)
            raise
        print('PASS '+suite+'; log: '+str(log), flush=True)
        observed = (suite,) if suite in ARC_SUITES else ()
    for name in observed:
        # Only freshly executed ARC workloads contribute evidence; an unrelated old report is never reused.
        print('ARC '+name+': '+json.dumps(unit_evidence(compiler, name), sort_keys=True), flush=True)


# Select a discovered suite before provisioning; full discovery remains the default supported behavior.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=UNIT_SUITES, help='Run one discovered native suite only')
    arguments = parser.parse_args()
    from setup_nimony import installed
    compiler, _ = installed()
    if arguments.suite is not None:
        # Pure, unprepared suites need no foreign libraries or generated integration fixtures.
        profile = NATIVE_REQUIREMENTS[arguments.suite]
        if not profile['libraries'] and not profile['prepared']:
            run_units(compiler, {}, {}, arguments.suite)
            return
    from native_preparation import prepare_libraries, prepare_integration, prepare_unit_fixtures, prepare_selected_fixture
    folder = ROOT/'build/tests/native/preparation'
    folder.mkdir(parents=True, exist_ok=True)
    # Preserve filenames and immediate progress logs when a later preparation stage fails.
    evidence_files = {
        'crypto_native': 'preparation',
        'bandersnatch_native': 'bandersnatch-preparation',
        'quic_native': 'quic-preparation',
        'pvm_gas_fixture': 'pvm-gas-preparation',
        'pvm_step_fixture': 'pvm-step-preparation',
        'store_replay_fixture': 'store-preparation',
        'authorization_stf_fixture': 'authorization-preparation',
        'history_stf_fixture': 'history-preparation',
        'signing_domain_fixture': 'signing-preparation',
        'entropy_stf_fixture': 'entropy-preparation',
        'ticket_stf_fixture': 'ticket-preparation',
        'sealer_stf_fixture': 'sealer-preparation',
        'validator_stf_fixture': 'validator-preparation',
    }
    if arguments.suite is not None:
        # Selection is validated by argparse and may own fresh evidence without overwriting sibling observations.
        evidence_files['selected_unit_fixture'] = 'selected-'+arguments.suite+'-preparation'
    # Write each completed stage before shared preparation starts the next potentially failing one.
    def record(name, evidence):
        (folder/(evidence_files[name]+'.json')).write_text(json.dumps(evidence, indent=2)+'\n')
    if arguments.suite is not None:
        # Library and fixture requirements are selected before any provider or integration corpus runs.
        libraries, certificates, _ = prepare_libraries(folder, record, required=profile['libraries'])
        fixtures = {}
        if profile['prepared']:
            # Checked-in static fixtures come from discovered contracts; generate only declared fresh inputs.
            fixtures, _ = prepare_selected_fixture(folder, arguments.suite, certificates, record)
        run_units(compiler, libraries, fixtures, arguments.suite)
        return
    libraries, certificates, _ = prepare_libraries(folder, record)
    wires, reload, _ = prepare_integration(folder)
    fixtures, _ = prepare_unit_fixtures(folder, certificates, wires, reload, record)
    # Shared preparation remains unchanged; focused runs select only their own validated fixture manifest.
    run_units(compiler, libraries, fixtures, arguments.suite)


# Imports expose profiles without provisioning dependencies or running tests.
if __name__ == '__main__':
    main()
