#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Private CI-only DOOM comparison of exact production interpretation/JIT and retained eager policy.

Fast untraced reference calls use a mutable instance; native calls include public immutable publication.
All lifecycle brackets remain separate and no total is described as ownership-equivalent.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import tarfile

from native_checks import NativeChecks, ROOT
from pvm_benchmark import cpu_model
from pvm_doom_attribution import BUILD as DOOM, run as prepare_doom
from pvm_doom_backends import observation, compare, rgba_frames, event_hashes, negative_frames
from pvm_guest_compare import unchanged
from pvm_guest_inputs import digest
from pvm_jit_platform import native_defines
from pvm_native_ci import host_identity
from setup_nimony import installed, cache_directory

MASTER = '387b90ff4a29273d97e5a424e8eda1871898e05b'
EAGER = '17672e5a0fe9992027e502da216f054ae0bab583'
BUILD = ROOT/'build/tests/pvm-doom-timing'
REPEATS, DISCARDED = 13, 3
ROLES = ('production-interpreted', 'production-jit', 'experimental-eager', 'reference-untraced')
COHORT = 'polkavm-interpreted,interpreted,jit,compiled'


def replace_once(source, old, new):
    """Source drift fails before compiling a projection; never guess a changed kernel boundary."""
    if source.count(old) != 1:
        raise ValueError('projection anchor differs: '+old[:100])
    return source.replace(old, new, 1)


def unsigned(value):
    """Every counter and duration is a canonical bounded nonnegative integer, never a synthetic timing zero."""
    if not value.isascii() or not value.isdecimal() or len(value) > 20 or int(value) >= 2**64:
        raise ValueError('invalid measurement integer')
    return int(value)


def native_projection(source):
    """Bracket the existing constructor/call/reset without changing the two-call host or state logic."""
    source = source.replace('../../src/', '../src/')
    source = replace_once(source, '\n\ntype\n', '''

proc cpuNanoseconds(): int64 {.importc: "pvm_sieve_cpu_nanoseconds", header: "pvm_sieve_clock.h".}
  ## Use the maintained fail-closed OS process CPU clock, with no guest clock or diagnostic timer.

type
''')
    start = source.index('proc eagerSnapshot(')
    stop = source.index('var current = source', start)
    source = source[:start]+'''proc eagerSnapshot(policy: PreparedInfo): string =
  ## Frozen construction receipts are outside every CPU measurement; old accepted APIs omit unavailable fields.
  when declared(PreparedCompilationInfo):
    let c = policy.compilation
    var passes = 0'u64
    when defined(pvmSourceSealingReceipt): passes = c.compilationPasses
    $int(c.sealed) & "," & $policy.streamNodes & "," & $policy.preparationUnits & "," &
      $policy.nativeFragments & "," & $policy.nativeCodeBytes & "," & $policy.nativeCompilationNs & "," &
      $c.sourceEntries & "," & $c.nativeEntries & "," & $c.checkedEntries & "," &
      $c.capacityDeferred & "," & $passes
  else:
    ""

var prepared = default(PreparedProgram)
block:
  # Only the actual public constructor is measured; the temporary result leaves this scope before retirement.
  let started = cpuNanoseconds()
  let made = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(1000000)), selected.pvmBackend)
  let elapsed = cpuNanoseconds()-started
  if made.error != PreparationError.None:
    echo "DOOM_BACKEND_UNAVAILABLE,", selected.pvmBackend, ",", made.error
    quit 2
  prepared = made.value
  echo "EARLY_PREPARE,", elapsed
var construction = ""
if selected.pvmBackend == PvmBackend.Compiled:
  when declared(PreparedCompilationInfo):
    # A missing eager facility or all-checked constructor cannot supply this experiment's native witness.
    let before = preparedInfo(prepared).value
    assert eagerCohort and before.backend == PvmBackend.Compiled and before.compilation.sealed
    assert before.compilation.nativeEntries > 0 and before.nativeFragments > 0 and before.nativeCodeBytes > 0
    assert before.nativeCalls == 0 and before.nativeOperations == 0
    construction = eagerSnapshot(before)
    echo "DOOM_EAGER_PREPARED,", construction
  else:
    assert false, "accepted baseline has no eager owner API"
''' + source[stop:]
    source = replace_once(source, '  let done = executeWithHost(current, context, respond, ExecutionStepLimit(1000000000),\n      HostCallLimit(4096), prepared)', '''  let callStart = cpuNanoseconds()
  let done = executeWithHost(current, context, respond, ExecutionStepLimit(1000000000),
      HostCallLimit(4096), prepared)
  let callElapsed = cpuNanoseconds()-callStart
  echo "EARLY_CALL,", call, ",", callElapsed''')
    source = replace_once(source, '    assert reused == construction and policy.compilation == compilation,',
                          '    assert reused == construction,')
    source = replace_once(source, '  current = captureMachine(owner, finalMemory, info).value', '''  let resetStart = cpuNanoseconds()
  current = captureMachine(owner, finalMemory, info).value
  let resetElapsed = cpuNanoseconds()-resetStart
  echo "EARLY_ABI_RESET,", call, ",", resetElapsed''')
    source += '''
# Drop the only remaining prepared handle after all outputs and checks; immutable input remains caller-owned.
let retireStart = cpuNanoseconds()
prepared = default(PreparedProgram)
let retireElapsed = cpuNanoseconds()-retireStart
echo "EARLY_RETIRE,", retireElapsed
'''
    return source


def project_native(source):
    """Extend only private selection and disjoint outer CPU scopes; checked guest/host loops stay intact."""
    source = native_projection(source)
    source = replace_once(source, '''assert requestedCohort in ["", "polkavm-interpreted,interpreted",
    "polkavm-interpreted,jit,compiled"],''',
                          'assert requestedCohort == "'+COHORT+'",')
    for name, old in (('interpretedCohort', 'polkavm-interpreted,interpreted'),
                      ('eagerCohort', 'polkavm-interpreted,jit,compiled')):
        # All modes remain explicit opt-ins in the same native-enabled production image.
        source = replace_once(source, f'let {name} = requestedCohort == "{old}"',
                              f'let {name} = requestedCohort == "{COHORT}"')
    source = replace_once(source, 'let loaded = loadArtifact(selected.pvmCodePath)',
                          'let artifactStart = cpuNanoseconds()\nlet loaded = loadArtifact(selected.pvmCodePath)')
    source = replace_once(source, 'let guestArtifact = loaded.value',
                          'let guestArtifact = loaded.value\necho "EARLY_ARTIFACT,", cpuNanoseconds()-artifactStart')
    source = replace_once(source, 'var images: seq[PageImage] = @[]',
                          'let restoreStart = cpuNanoseconds()\nvar images: seq[PageImage] = @[]')
    source = replace_once(source, 'let source = captureMachine(owner, captured.value, info).value',
                          'let source = captureMachine(owner, captured.value, info).value\n'
                          'echo "EARLY_RESTORE,", cpuNanoseconds()-restoreStart')
    source = replace_once(source, '  let policy = preparedInfo(prepared).value', '''  let policy = preparedInfo(prepared).value
  let nativeOwner = preparedArmStatistics(prepared).value
  assert nativeOwner[0] == policy.nativeFragments and nativeOwner[1] == policy.nativeCalls
  assert nativeOwner[2] == policy.nativeOperations and nativeOwner[3] == policy.nativeCodeBytes
  assert nativeOwner[4] == policy.nativeCompilationNs
  assert policy.checkedFallbackEnabled == (selected.pvmBackend in [PvmBackend.Jit, PvmBackend.Compiled])
  if selected.pvmBackend == PvmBackend.Interpreted:
    # This is the same native-enabled production image, with every copied native owner counter zero.
    assert nativeOwner == default(array[7, uint64])
  echo "EARLY_OWNER,", call, ",", nativeOwner[0], ",", nativeOwner[1], ",", nativeOwner[2],
    ",", nativeOwner[3], ",", nativeOwner[4], ",", nativeOwner[5], ",", nativeOwner[6],
    ",", int(policy.checkedFallbackEnabled)''')
    return source


DOOM_MAIN = r'''
// Private two-call continuation: use the maintained interpreter, host dispatch and complete state methods.
fn main() {
    let args: Vec<String> = std::env::args().collect();
    assert_eq!(args.len(), 5);
    if std::env::var("RAGNAROK_PVM_DOOM_ASSERT").as_deref() == Ok("1") {
        panic!("doom reference assertion control");
    }
    let raw = fs::read(&args[1]).unwrap();
    let rom = fs::read(&args[2]).unwrap();
    assert_eq!(rom.len(), 4196020);
    let folder = Path::new(&args[3]);
    let output = Path::new(&args[4]);
    let input = fs::read(folder.join("tick.input")).unwrap();
    let wanted = fs::read(folder.join("tick.expected")).unwrap();
    let wanted_events = fs::read(folder.join("tick.events")).unwrap();
    let started = cpu_nanoseconds();
    let guest = Guest::load(raw);
    let prepared = cpu_nanoseconds()-started;
    println!("FAST_MODE,interpreter,step_tracing=false");
    println!("FAST_PREPARE,{prepared}");
    let restore_start = cpu_nanoseconds();
    let mut instance = guest.module.instantiate().unwrap();
    guest.reset(&mut instance, 1);
    let mut cursor = 152+guest.wire.len();
    assert_eq!(input.len(),cursor+guest.pages.len()*4101);
    for &(address, access) in &guest.pages {
        assert_eq!(word(&input,cursor,4),u64::from(address/4096));
        assert_eq!(input[cursor+4],access);
        let bytes=&input[cursor+5..cursor+4101];
        if access==2 { instance.write_memory(address,bytes).unwrap(); }
        else { assert_eq!(instance.read_memory(address,4096).unwrap(),bytes); }
        cursor+=4101;
    }
    let restore=cpu_nanoseconds()-restore_start;
    assert!(guest.input(&mut instance,1)==input,"DOOM initial state mismatch");
    println!("FAST_RESTORE,0,{restore}");
    for call in 0..2 {
        let started=cpu_nanoseconds();
        let events=guest.run(&mut instance,&rom);
        let elapsed=cpu_nanoseconds()-started;
        let state=guest.expected(&mut instance);
        let encoded=events.encode();
        if call==0 {
            assert!(state==wanted,"DOOM terminal state mismatch");
            assert!(encoded==wanted_events,"DOOM event mismatch");
        }
        // Normalize the proved Finished/PC-none terminal state into the shared public observation framing.
        let mut canonical=Vec::new();
        canonical.extend(0u64.to_le_bytes());
        canonical.extend(&state[8..16]);
        canonical.extend(0u64.to_le_bytes());
        canonical.push(1);
        canonical.extend(&state[16..120]);
        for (index,&(address,access)) in guest.pages.iter().enumerate() {
            canonical.extend((address/4096).to_le_bytes());
            canonical.push(access);
            canonical.extend(&state[120+index*4096..120+(index+1)*4096]);
        }
        fs::write(output.join(format!("call-{call}.state")),canonical).unwrap();
        fs::write(output.join(format!("call-{call}.events")),encoded).unwrap();
        fs::write(output.join(format!("call-{call}.hosts")),events.host_trace).unwrap();
        println!("FAST_CALL,{call},{elapsed}");
        let started=cpu_nanoseconds();
        guest.reset(&mut instance,1);
        let reset=cpu_nanoseconds()-started;
        println!("FAST_ABI_RESET,{call},{reset}");
    }
    let started=cpu_nanoseconds();
    drop(instance);
    drop(guest);
    let retired=cpu_nanoseconds()-started;
    println!("FAST_RETIRE,{retired}");
    println!("FAST_SEQUENCE_OK,doom,2");
}
'''


def reference_projection(source):
    """Preserve the maintained run/expected/reset code; add only ordered host receipts and continuation orchestration."""
    source=source[:source.index('// Prepare once; measured/profiled execution reads')]+DOOM_MAIN
    source=replace_once(source,'use std::{fs, path::Path};','use std::{fs, path::Path};\nuse std::fmt::Write;')
    source=replace_once(source,'    fn load(path: &Path) -> Self {','    fn load(raw: Vec<u8>) -> Self {')
    source=replace_once(source,'        let raw = fs::read(path).unwrap();','')
    source=replace_once(source,'        profile.set_page_size(4096);',
                        '        profile.set_page_size(4096);\n        profile.set_step_tracing(false);')
    source=replace_once(source,'struct Events {\n    records:', 'struct Events {\n    host_trace: String,\n    records:')
    source=replace_once(source,'        let mut events = Events {\n            records:',
                        '        let mut events = Events {\n            host_trace: String::new(),\n            records:')
    source=replace_once(source,'                    let c = instance.reg(Reg::A2);',
                        '                    let c = instance.reg(Reg::A2);\n                    writeln!(&mut events.host_trace,"{kind},{a},{b},{c}").unwrap();')
    return source


def reference_timing(output,family):
    """Keep fast mutable-instance call scopes separate from restore/teardown and public immutable publication."""
    rows=[line.split(',') for line in output.splitlines()]
    if family != 'doom' or [r[0] for r in rows] != ['FAST_MODE', 'FAST_PREPARE',
            'FAST_RESTORE', 'FAST_CALL', 'FAST_ABI_RESET', 'FAST_CALL', 'FAST_ABI_RESET',
            'FAST_RETIRE', 'FAST_SEQUENCE_OK']:
        raise ValueError('incomplete or reordered untraced DOOM lifecycle')
    assert rows.count(['FAST_MODE','interpreter','step_tracing=false'])==1
    assert rows[-1]==['FAST_SEQUENCE_OK',family,'2']
    prepare=[r for r in rows if r[0]=='FAST_PREPARE'];retire=[r for r in rows if r[0]=='FAST_RETIRE']
    calls=[r for r in rows if r[0]=='FAST_CALL']
    if len(prepare)!=1 or len(retire)!=1 or len(calls)!=2: raise ValueError('incomplete untraced reference')
    if len(prepare[0]) != 2 or len(retire[0]) != 2:
        raise ValueError('malformed reference construction/retirement')
    for i,row in enumerate(calls):
        assert len(row)==3 and row[1]==str(i)
    measured=dict(constructor_cpu_ns=unsigned(prepare[0][1]),calls_cpu_ns=[unsigned(r[-1]) for r in calls],
        retirement_cpu_ns=unsigned(retire[0][1]))
    if measured['constructor_cpu_ns']<=0 or min(measured['calls_cpu_ns'])<=0: raise ValueError('missing CPU clock')
    for tag,key,count in [('FAST_RESTORE','instance_restore_cpu_ns',1),
                          ('FAST_ABI_RESET','external_abi_reset_cpu_ns',2)]:
        items=[r for r in rows if r[0]==tag]
        if len(items)!=count or any(len(r)!=3 or r[1]!=str(i) for i,r in enumerate(items)):
            raise ValueError('incomplete fast lifecycle: '+tag)
        if count: measured[key]=[unsigned(r[2]) for r in items]
    return measured


def reference_observation(output,folder,pages):
    """Read actual fast terminal state/events/ordered hosts; compare through the maintained full-state comparator."""
    measured=reference_timing(output,'doom')
    result=dict(requested='polkavm-interpreted-fast',calls=[],frames=[])
    for call in range(2):
        state,events,hosts=(folder/f'call-{call}.{suffix}' for suffix in ('state','events','hosts'))
        data=state.read_bytes();raw=events.read_bytes()
        assert len(data)==129+pages*4101 and len(raw)<=4*1024*1024 and hosts.stat().st_size<=512*1024
        result['frames']+=rgba_frames(raw,call,len(result['frames']))
        result['calls'].append(dict(call=call,actual='polkavm-interpreted-fast',gas=int.from_bytes(data[8:16],'little'),
            fragments=0,native_calls=0,native_operations=0,state_sha256=digest(state),
            events_sha256=event_hashes(raw)['sha256'],hosts_sha256=digest(hosts)))
    return result


def native_timing(output):
    """Decode exactly the disjoint native clocks; immutable result publication stays inside each call."""
    rows = [line.split(',') for line in output.splitlines()
            if line.startswith('EARLY_') and not line.startswith('EARLY_OWNER,')]
    tags = ['EARLY_ARTIFACT', 'EARLY_RESTORE', 'EARLY_PREPARE', 'EARLY_CALL',
            'EARLY_ABI_RESET', 'EARLY_CALL', 'EARLY_ABI_RESET', 'EARLY_RETIRE']
    if [r[0] for r in rows] != tags:
        raise ValueError('incomplete or reordered native lifecycle clocks')
    values = {}
    for tag, key in (('EARLY_ARTIFACT', 'artifact_load_cpu_ns'),
                     ('EARLY_RESTORE', 'instance_restore_cpu_ns'),
                     ('EARLY_PREPARE', 'constructor_cpu_ns'),
                     ('EARLY_RETIRE', 'retirement_cpu_ns')):
        row = next(r for r in rows if r[0] == tag)
        if len(row) != 2:
            raise ValueError('malformed native clock: '+tag)
        values[key] = unsigned(row[1])
    for tag, key in (('EARLY_CALL', 'calls_cpu_ns'),
                     ('EARLY_ABI_RESET', 'external_abi_reset_cpu_ns')):
        selected = [r for r in rows if r[0] == tag]
        if any(len(r) != 3 or r[1] != str(i) for i, r in enumerate(selected)):
            raise ValueError('malformed native call/reset clocks')
        values[key] = [unsigned(r[2]) for r in selected]
    if values['constructor_cpu_ns'] <= 0 or min(values['calls_cpu_ns']) <= 0:
        raise ValueError('missing real native CPU duration')
    return values


def native_observation(output, folder, selected, pages, architecture):
    """Bind full checked output to seven actual owner counters, including native-zero forced interpretation."""
    rows = [line.split(',') for line in output.splitlines() if line.startswith('EARLY_OWNER,')]
    if len(rows) != 2 or any(len(r) != 10 or r[1] != str(i) for i, r in enumerate(rows)):
        raise ValueError('missing ordered native owner observations')
    clean = '\n'.join(line for line in output.splitlines() if not line.startswith('EARLY_'))+'\n'
    observed = observation(clean, folder, selected, 2, pages, architecture)
    for row, call in zip(rows, observed['calls']):
        values = list(map(unsigned, row[2:9]))
        if values[:3] != [call['fragments'], call['native_calls'], call['native_operations']]:
            raise ValueError('owner and policy counters disagree')
        if selected == 'interpreted' and any(values):
            raise ValueError('forced interpretation published native activity')
        if row[9] != str(int(selected in ('jit', 'compiled'))):
            raise ValueError('unexpected actual fallback policy')
        if call['call'] and selected in ('jit', 'compiled') and any(
                values[index] <= observed['calls'][0]['native_owner'][index] for index in (1, 2)):
            raise ValueError('continuing call did not execute actual native work')
        call['native_owner'] = values
        call['checked_fallback_enabled'] = bool(unsigned(row[9]))
    return observed


def git(*args):
    """Read immutable source identities with Git; no refs or upstream sources are modified."""
    return subprocess.check_output(['git', *args], cwd=ROOT)


def unpack(revision, destination):
    """Copy the complete owned source/JIT tree without altering a single production runtime byte."""
    if destination.exists():
        shutil.rmtree(destination)  # Only this helper's private staging directory is replaced serially.
    destination.mkdir()
    raw = git('archive', revision, 'src', 'native/pvm_jit')
    with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
        for item in archive:
            if item.isdir():
                continue  # Only ordinary owned source blobs can become compiler inputs.
            if not item.isfile() or Path(item.name).is_absolute() or '..' in Path(item.name).parts:
                raise ValueError('foreign source archive member')
            path = destination/item.name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(archive.extractfile(item).read())


def build_reference(checks, command):
    """Build only the DOOM untraced adapter twice, using pristine pinned dependencies at fixed paths."""
    original = ROOT/'tests/performance/polkavm_doom'
    target = BUILD/'reference-source'
    (target/'src').mkdir(parents=True, exist_ok=True)
    for name in ('Cargo.toml', 'Cargo.lock'):
        text = (original/name).read_text()
        if name == 'Cargo.toml':
            # Only crate-relative vendor locations change; package features, versions and locks are fixed.
            text = text.replace('../../../vendor/polkavm/', str(ROOT/'vendor/polkavm')+'/')
        (target/name).write_text(text)
    for path in sorted((original/'src').glob('*.rs')):
        text = path.read_text()
        if path.name == 'main.rs':
            text = reference_projection(text)
        (target/'src'/path.name).write_text(text)
    rust = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
    provenance = dict(original={str(p.relative_to(ROOT)):digest(p) for p in
        [*sorted((original/'src').glob('*.rs')), original/'Cargo.toml', original/'Cargo.lock']},
        projected={str(p.relative_to(ROOT)):digest(p) for p in sorted(target.rglob('*')) if p.is_file()},
        rust=rust, backend='Interpreter', step_tracing=False, builds=[])
    binary = BUILD/'reference-target/release/ragnarok-pvm-doom'
    pairs = []
    for repeat in range(2):
        # Fresh private crate compilation retains unchanged dependency objects, not an earlier main image.
        command(['rustup', 'run', rust, 'cargo', 'clean', '--release', '--package',
                 'ragnarok-pvm-doom', '--manifest-path', target/'Cargo.toml',
                 '--target-dir', BUILD/'reference-target'], f'reference-{repeat}-clean', timeout=300)
        row = command(['rustup', 'run', rust, 'cargo', 'build', '--release', '--locked', '--offline',
                       '--manifest-path', target/'Cargo.toml', '--target-dir', BUILD/'reference-target'],
                      f'reference-{repeat}-build', timeout=900)
        provenance['builds'].append(row)
        saved = BUILD/f'reference-{repeat}'
        shutil.copy2(binary, saved)
        pairs.append(saved)
    if pairs[0].read_bytes() != pairs[1].read_bytes():
        raise ValueError('fresh untraced reference images differ')
    return pairs[0], provenance


def matrix():
    """Prespecify all fresh processes: one forward and one reverse order, three discarded plus ten retained."""
    return [(order, sample, role) for order, roles in enumerate((ROLES, ROLES[::-1]))
            for sample in range(REPEATS) for role in roles]


def statistics_for(values):
    """Report raw CPU median and range; sample counts never include discarded fresh processes."""
    if len(values) != REPEATS-DISCARDED:
        raise ValueError('incomplete retained CPU scope')
    return dict(median=statistics.median(values), minimum=min(values), maximum=max(values),
                samples=len(values))


def summarize(runs):
    """Reparse raw process clocks and calculate per-order ratios against the same-runner untraced reference."""
    if [(r['order'], r['sample'], r['role']) for r in runs] != matrix():
        raise ValueError('incomplete or unbalanced DOOM process matrix')
    rows = []
    for order in (0, 1):
        roles = {}
        for role in ROLES:
            selected = [r for r in runs if r['order'] == order and r['role'] == role]
            if any(r['discarded'] != (r['sample'] < DISCARDED) for r in selected):
                raise ValueError('changed discard policy')
            for r in selected:
                # Raw stdout is authoritative even if a stored parsed field was tampered with.
                parsed = (reference_timing(r['run']['output'], 'doom') if role == ROLES[-1]
                          else native_timing(r['run']['output']))
                if parsed != r['measured']:
                    raise ValueError('changed parsed CPU record')
            measured = [r['measured'] for r in selected if not r['discarded']]
            scopes = dict(constructor=[r['constructor_cpu_ns'] for r in measured],
                initial_restore=[(r['instance_restore_cpu_ns'][0] if role == ROLES[-1]
                                  else r['instance_restore_cpu_ns']) for r in measured],
                first_call=[r['calls_cpu_ns'][0] for r in measured],
                continuing_call=[r['calls_cpu_ns'][1] for r in measured],
                reset_after_first=[r['external_abi_reset_cpu_ns'][0] for r in measured],
                reset_after_second=[r['external_abi_reset_cpu_ns'][1] for r in measured],
                retirement=[r['retirement_cpu_ns'] for r in measured])
            if role != ROLES[-1]:
                scopes['artifact_load'] = [r['artifact_load_cpu_ns'] for r in measured]
            # This is only the sum of recorded disjoint scopes per sample; omitted ownership differs.
            scopes['available_lifecycle_subtotal'] = [sum(values[i] for values in scopes.values())
                                                       for i in range(len(measured))]
            roles[role] = {name:statistics_for(values) for name, values in scopes.items()}
        reference = roles[ROLES[-1]]
        ratios = {role:{scope:roles[role][scope]['median']/reference[scope]['median']
                       for scope in ('first_call', 'continuing_call', 'available_lifecycle_subtotal')}
                  for role in ROLES[:-1]}
        rows.append(dict(order=order, cpu_ns=roles, ours_over_reference=ratios,
                         lifecycle_subtotal_ownership_equivalent=False))
    return rows


def run():
    """Qualify exact source/images and full continuation state before admitting same-runner timing data."""
    if os.environ.get('GITHUB_ACTIONS') != 'true' or platform.system() != 'Linux':
        raise RuntimeError('native compilation and DOOM execution are Linux CI-only')
    host = host_identity()
    if host['architecture'] not in ('arm64', 'x86_64'):
        raise RuntimeError('DOOM comparison requires an actual supported native CPU')
    BUILD.mkdir(parents=True, exist_ok=True)
    checks = NativeChecks(BUILD)
    report = dict(status='incomplete', protocol='doom-three-engines-untraced-v1',
        production=MASTER, experimental_eager=EAGER, host=host, cpu=cpu_model(), warmup_ticks=1320,
        calls_per_owner=2, samples_per_order=REPEATS, discarded_per_order=DISCARDED,
        role_order=list(ROLES), source_maps={}, builds=[], controls=[], runs=[], images={}, summary=[],
        scopes=dict(native_call='executeWithHost including callbacks and immutable result publication; serialization/checks excluded',
            reference_call='Guest.run on mutable RawInstance including callbacks; serialization/checks excluded',
            native_artifact_load='loadArtifact file read/parse and immutable owner publication; fixture decode excluded',
            native_restore='PageImage construction plus captureMemory/captureMachine from immutable warmed fixture',
            reference_restore='instantiate plus reset and restored writes/readonly checks on the mutable instance',
            native_constructor='newPreparedProgram only; public interpreted/JIT modes share one production image',
            reference_constructor='Guest.load from pre-read raw bytes: parse/validate, Engine/Module and page facts',
            native_retirement='final prepared handle only; immutable caller-owned artifact/memory remain live',
            reference_retirement='drop mutable instance plus Guest/module',
            immutable_publication_within_call_cpu_ns=None,
            lifecycle_subtotals='Sum of recorded disjoint scopes, with different retained/omitted ownership; NOT equivalent totals'))

    def save():
        """Retain incomplete evidence immediately, after each process and on every exception."""
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')

    def command(args, name, environment=None, timeout=900, required=True):
        """Preserve exact arguments, output and status; a failed process supplies no timing sample."""
        row = checks.command(args, name, environment=environment, timeout=timeout)
        if required and row['exit_code']:
            raise RuntimeError(name+' failed: '+row['output'][-2000:])
        return row

    save()
    try:
        report['revision'] = git('rev-parse', 'HEAD').decode().strip()
        for source in (MASTER, EAGER):
            # Source absence must fail before any compiler, fixture preparation or guest process.
            if git('rev-parse', source+'^{commit}').decode().strip() != source:
                raise ValueError('immutable comparison source is unavailable')
        if git('show', EAGER+':spec/toolchain.json') != (ROOT/'spec/toolchain.json').read_bytes():
            raise ValueError('experimental source uses another compiler pin')
        compiler, _ = installed()
        report['compiler'] = dict(path=str(compiler.relative_to(ROOT)), sha256=digest(compiler),
            identity=(compiler.parent.parent/'NIGHTLY.txt').read_text(),
            clang=subprocess.check_output(['clang', '--version'], text=True))
        report['pins'] = {name:json.loads((ROOT/'spec'/name).read_text()) for name in
                          ('toolchain.json', 'polkavm-pins.json', 'bandersnatch-pins.json', 'pvm-doom-assets.json')}
        report['rust_compiler'] = command(['rustup', 'run', report['pins']['bandersnatch-pins.json']['rust'],
                                          'rustc', '--version', '--verbose'], 'rust-compiler-identity')
        cpu = command(['lscpu', '--json'], 'cpu-identity', dict(os.environ, LC_ALL='C'))
        report['cpu_details'] = json.loads(cpu['output'])
        # Maintained correctness preparation supplies the pristine linked guest, frame1320 oracle and tamper controls.
        prepare_doom(check_only=True, warmup=1320)
        admission = json.loads((DOOM/'results.json').read_text())
        if admission['status'] != 'checks-passed' or not admission.get('golden_rgba_sha256'):
            raise ValueError('complete warmed DOOM golden preparation is missing')
        report['admission'] = admission
        input_paths = [DOOM/'doom.polkavm', *sorted((DOOM/'prepared').glob('*')),
                       ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad']
        identities = {p:digest(p) for p in input_paths}
        identities[compiler] = digest(compiler)
        owned = [*sorted((ROOT/'tools').glob('*.py')), ROOT/'Makefile', ROOT/'.github/workflows/ci.yml',
                 ROOT/'tests/interop/pvm_doom_backends.nim', ROOT/'tests/performance/pvm_sieve_clock.h',
                 *(ROOT/'spec'/name for name in report['pins'])]
        identities.update({p:digest(p) for p in owned})
        driver = project_native((ROOT/'tests/interop/pvm_doom_backends.nim').read_text())
        (BUILD/'consumer.nim').write_text(driver)
        images = {}
        for endpoint, revision in (('production', MASTER), ('experimental', EAGER)):
            # Serial exact archives use the same source, cache and output paths for reproducible code generation.
            canonical = BUILD/'snapshot'
            unpack(revision, canonical)
            (canonical/'benchmarks').mkdir()
            main = canonical/'benchmarks/doom.nim'
            main.write_text(driver)
            pair = []
            for repeat in range(2):
                cache = cache_directory(compiler, BUILD, 'engine')
                if cache.exists():
                    shutil.rmtree(cache)  # Fresh compiler work is private to this exact endpoint/build.
                built, binary = checks.build(compiler, main, 'engine',
                    defines=[*native_defines(), 'pvmSourceSealingReceipt', 'pvmArm64JitOwnerReceipt'],
                    cflags=['-D_GNU_SOURCE', '-I'+str(ROOT/'tests/performance'),
                            '-I'+str(canonical/'native/pvm_jit')])
                name = f'{endpoint}-{repeat}'
                shutil.copyfile(BUILD/'engine-build.log', BUILD/(name+'-build.log'))
                built['log'] = str((BUILD/(name+'-build.log')).relative_to(ROOT))
                report['builds'].append(dict(endpoint=endpoint, repeat=repeat, run=built))
                save()
                if built['exit_code']:
                    raise RuntimeError(name+' build failed: '+built['output'][-2000:])
                saved = BUILD/name
                shutil.copy2(binary, saved)
                pair.append(saved)
                identities[saved] = digest(saved)
            if pair[0].read_bytes() != pair[1].read_bytes():
                raise ValueError('fresh native image equality failed: '+endpoint)
            images[endpoint] = pair[0]
            report['source_maps'][endpoint] = {str(p.relative_to(canonical)):digest(p)
                for p in sorted(canonical.rglob('*')) if p.is_file()}
        images['reference'], report['reference_sources'] = build_reference(checks, command)
        for group in ('original', 'projected'):
            identities.update({ROOT/path:sha for path, sha in report['reference_sources'][group].items()})
        for repeat in range(2):
            identities[BUILD/f'reference-{repeat}'] = digest(BUILD/f'reference-{repeat}')
        report['images'] = {name:digest(path) for name, path in images.items()}
        report['identities'] = {str(p.relative_to(ROOT)):sha for p, sha in identities.items()}
        # Retained input bytes make linked guest, fixture and WAD identities independently auditable.
        for path in input_paths:
            dest = BUILD/'retained-inputs'/path.relative_to(ROOT)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, dest)
        pages = int.from_bytes((DOOM/'prepared/tick.input').read_bytes()[16:20], 'little')
        if not 0 < pages <= 8192:
            raise ValueError('invalid warmed fixture page count')
        output = BUILD/'raw-output'
        output.mkdir(exist_ok=True)
        common = dict(os.environ, PVM_DOOM_BACKENDS=COHORT, RAGNAROK_PVM_DOOM_INPUT=str(DOOM/'prepared'),
            RAGNAROK_PVM_DOOM_ROM=str(ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad'),
            RAGNAROK_DOOM_BACKEND_CALLS='2', RAGNAROK_DOOM_BACKEND_ASSERT='0',
            RAGNAROK_PVM_DOOM_ASSERT='0', RAGNAROK_DOOM_BACKEND_OUTPUT=str(output))
        args_for = {'production-interpreted':[images['production'], '--pvm-code', DOOM/'doom.polkavm',
                        '--pvm-entry', 'ext_tick', '--pvm-backend', 'interpreted'],
                    'production-jit':[images['production'], '--pvm-code', DOOM/'doom.polkavm',
                        '--pvm-entry', 'ext_tick', '--pvm-backend', 'jit'],
                    'experimental-eager':[images['experimental'], '--pvm-code', DOOM/'doom.polkavm',
                        '--pvm-entry', 'ext_tick', '--pvm-backend', 'compiled'],
                    'reference-untraced':[images['reference'], DOOM/'doom.polkavm',
                        common['RAGNAROK_PVM_DOOM_ROM'], DOOM/'prepared', output]}
        reference_run = command(args_for[ROLES[-1]], 'continuing-reference', common)
        reference = reference_observation(reference_run['output'], output, pages)
        if reference['frames'][0]['rgba_sha256'] != admission['golden_rgba_sha256']:
            raise ValueError('untraced reference differs from upstream frame1320 golden')
        golden = {(call, suffix):(output/f'call-{call}.{suffix}').read_bytes()
                  for call in range(2) for suffix in ('state', 'events', 'hosts')}
        retained = BUILD/'retained-output/reference-oracle'
        retained.mkdir(parents=True, exist_ok=True)
        for (call, suffix), raw in golden.items():
            (retained/f'call-{call}.{suffix}').write_bytes(raw)
        report['reference'] = dict(run=reference_run, observed=reference)
        for role in ROLES:
            # Every executed image/selected native policy proves its intended active assertion independently.
            env = dict(common, **{'RAGNAROK_PVM_DOOM_ASSERT' if role == ROLES[-1]
                                 else 'RAGNAROK_DOOM_BACKEND_ASSERT':'1'})
            row = command(args_for[role], 'assert-'+role, env, required=False)
            needle = 'doom reference assertion control' if role == ROLES[-1] else 'DOOM backend assertion control'
            if row['exit_code'] == 0 or needle not in row['output']:
                raise ValueError('missing intended assertion failure: '+role)
            report['controls'].append(dict(role=role, control='active-assertion', run=row))
        for order, sample, role in matrix():
            # Only one fresh process runs at a time on this CPU runner; reverse order balances role position.
            unchanged(identities)
            row = command(args_for[role], f'order{order}-sample{sample}-{role}', common)
            if role == ROLES[-1]:
                measured = reference_timing(row['output'], 'doom')
                observed = reference_observation(row['output'], output, pages)
            else:
                selected = 'interpreted' if role == ROLES[0] else 'jit' if role == ROLES[1] else 'compiled'
                measured = native_timing(row['output'])
                observed = native_observation(row['output'], output, selected, pages, host['architecture'])
            compare(reference, observed, 2)
            for (call, suffix), raw in golden.items():
                if (output/f'call-{call}.{suffix}').read_bytes() != raw:
                    raise ValueError(f'{role} call{call} complete {suffix} differs')
            if order == sample == 0:
                dest = BUILD/'retained-output'/role
                dest.mkdir(parents=True, exist_ok=True)
                for call, suffix in golden:
                    shutil.copyfile(output/f'call-{call}.{suffix}', dest/f'call-{call}.{suffix}')
            report['runs'].append(dict(order=order, sample=sample, role=role,
                discarded=sample < DISCARDED, run=row, measured=measured, observed=observed))
            save()
        data = bytearray(golden[0, 'events'])
        at = 0
        while data[at] != 1:
            at += 5+int.from_bytes(data[at+1:at+5], 'little')
        data[at+5+8] ^= 1
        changed = rgba_frames(bytes(data), 0, 0)
        frames = changed+reference['frames'][len(changed):]
        report['controls'] += negative_frames(reference, report['runs'][0]['observed'], 2, frames)
        unchanged(identities)
        report['summary'] = summarize(report['runs'])
        report['status'] = 'passed'
        print(json.dumps(report['summary'], indent=2), flush=True)
    except BaseException as error:
        report['error'] = type(error).__name__+': '+str(error)
        raise
    finally:
        save()


if __name__ == '__main__':
    run()
