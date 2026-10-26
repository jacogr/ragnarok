#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Count actual PVM opcodes/pairs in ignored diagnostic snapshots; discard instrumented timings."""
import hashlib
import json
import os
import re

from native_checks import NativeChecks, ROOT
from native_fixture_contracts import load_fixture_contracts
from pvm_benchmark_report import NAMES, parse_output
from setup_nimony import installed


FIELDS = '''  CensusPair = object ## Diagnostic-only exact tags bound a pair's invocation-local frequency.
    tag: uint16
    count: uint64
'''
CACHE = '''    censusOps: array[256, uint64]
    censusPairs: array[512, CensusPair]
    censusPrevious: byte
    censusStarted: bool
    censusSteps: uint64
'''
HELPERS = '''proc recordCensus(cache: var ExecutionCache, opcode: byte) =
  ## Count only entered instruction evaluation, never decoder/pricing probes or another invocation's events.
  assert cache.censusSteps < high(uint64)
  assert cache.censusOps[int(opcode)] < high(uint64)
  inc cache.censusSteps
  inc cache.censusOps[int(opcode)]
  if cache.censusStarted:
    # Full byte tags distinguish every possible pair; bounded probing fails rather than dropping an unseen transition.
    let tag = uint16(cache.censusPrevious)*256'u16+uint16(opcode)
    var slot = int((uint64(tag)*11400714819323198485'u64) shr 55)
    var inserted = false
    for attempt in 0..<512:
      if cache.censusPairs[slot].count == 0 or cache.censusPairs[slot].tag == tag:
        assert cache.censusPairs[slot].count < high(uint64)
        cache.censusPairs[slot].tag = tag
        inc cache.censusPairs[slot].count
        inserted = true
        break
      slot = (slot+1) mod 512
    assert inserted, "opcode census pair capacity exceeded"
  cache.censusPrevious = opcode
  cache.censusStarted = true

proc reportCensus(cache: ExecutionCache) =
  ## Diagnostic rows are emitted only at completed guest/host terminal boundaries; benchmark timings are discarded by the caller.
  echo "census,begin,", cache.censusSteps
  for opcode in 0..<256:
    if cache.censusOps[opcode] > 0:
      echo "census,op,", opcode, ",", cache.censusOps[opcode]
  for entry in cache.censusPairs:
    if entry.count > 0:
      echo "census,pair,", int(entry.tag) div 256, ",", int(entry.tag) mod 256, ",", entry.count
  echo "census,end"

proc censusCapacityControl*() =
  ## Verification-only negative witness proves saturation cannot become a partial successful census.
  var cache = initExecutionCache()
  for previous in 0..<256:
    for opcode in 0..<256:
      cache.censusStarted = true
      cache.censusPrevious = byte(previous)
      recordCensus(cache, byte(opcode))

'''


def instrument_step(source, pair_capacity=512):
    """Every named mutation must match exactly once before any generated source can be compiled."""
    if pair_capacity not in (512, 4096):
        raise ValueError('unsupported opcode census pair capacity')
    # Diagnostic fields belong to the cache object, independently of tuned production field capacities.
    headers = re.findall(r'^  ExecutionCache = object(?:[ \t]+##[^\n]*)?\n', source, re.MULTILINE)
    if len(headers) != 1:
        raise ValueError('changed opcode census injection site: types')
    header = headers[0]
    cache = CACHE.replace('512', str(pair_capacity))
    helpers = HELPERS.replace('512', str(pair_capacity)).replace('shr 55', 'shr '+str(64-(pair_capacity.bit_length()-1)))
    replacements = [
      ('import', 'import ./[program, machine, registers, gas, gas_plan, gas_memo]',
       'import std/[assertions, syncio]\nimport ./[program, machine, registers, gas, gas_plan, gas_memo]'),
      ('types', header, FIELDS+header+cache),
      ('initialize', '  ExecutionCache(valid: false,', ('''  ExecutionCache(censusOps: default(array[256, uint64]), censusPairs: default(array[512, CensusPair]),
    censusPrevious: 0, censusStarted: false, censusSteps: 0, valid: false,''').replace('512', str(pair_capacity))),
      ('helpers', 'proc cachedSecondaryCharge(', helpers+'proc cachedSecondaryCharge('),
      ('event', '  if not info.blockCharged:', '  recordCensus(cache, item.opcode) # Diagnostic-only event after decoding/capability admission.\n  if not info.blockCharged:'),
      ('guest-terminal', '      return published\n  StepResult(status: StepError.StepLimitExceeded)',
       '''      if effect.kind != StepExit.Host: reportCensus(chargeCache)
      return published
  StepResult(status: StepError.StepLimitExceeded)'''),
      ('host-terminal', '''    if applied.effect.kind != StepExit.Continued:
      return publishInstruction(cursor.program, cursor.memory, cursor.info, applied.effect, true)''',
       '''    if applied.effect.kind != StepExit.Continued:
      reportCensus(chargeCache)
      return publishInstruction(cursor.program, cursor.memory, cursor.info, applied.effect, true)'''),
      ('fallible-terminal', '''      if applied.effect.kind != StepExit.Continued:
        return executionResult[Reason](publishInstruction(cursor.program, cursor.memory,''',
       '''      if applied.effect.kind != StepExit.Continued:
        reportCensus(chargeCache)
        return executionResult[Reason](publishInstruction(cursor.program, cursor.memory,''')]
    for label, before, _ in replacements:
        if source.count(before) != 1:
            raise ValueError('changed opcode census injection site: '+label)
    for _, before, after in replacements:
        source = source.replace(before, after, 1)
    return source

EXPECTED_STEPS = dict(zip(NAMES, (30001, 5001, 5001, 6001, 6001, 4, 49, 9001, 5001, 5001, 4001)))


def integer(text, low, high):
    """Accept only canonical bounded decimal counters; no sign/overflow/default coercion is allowed."""
    value = int(text)
    if str(value) != text or not low <= value <= high:
        raise ValueError('invalid census integer')
    return value


def parse_reports(output, pair_capacity=512):
    """Require complete opcode/pair conservation and invocation framing before accepting any census."""
    if pair_capacity not in (512, 4096):
        raise ValueError('unsupported opcode census pair capacity')
    reports, regular, current = [], [], None
    for line in output.splitlines():
        fields = line.split(',')
        if fields[0] != 'census':
            if current is not None:
                raise ValueError('interleaved census output')
            regular.append(line)
            continue
        if len(fields) == 3 and fields[1] == 'begin' and current is None:
            current = dict(steps=integer(fields[2], 1, (1 << 64)-1), opcodes={}, pairs={})
        elif len(fields) == 4 and fields[1] == 'op' and current is not None:
            opcode = integer(fields[2], 0, 255)
            count = integer(fields[3], 1, current['steps'])
            if opcode in current['opcodes']:
                raise ValueError('duplicate census opcode')
            current['opcodes'][opcode] = count
        elif len(fields) == 5 and fields[1] == 'pair' and current is not None:
            pair = (integer(fields[2], 0, 255), integer(fields[3], 0, 255))
            count = integer(fields[4], 1, current['steps'])
            if pair in current['pairs'] or len(current['pairs']) >= pair_capacity:
                raise ValueError('duplicate or excess census pair')
            current['pairs'][pair] = count
        elif fields == ['census', 'end'] and current is not None:
            ops, pairs, steps = current['opcodes'], current['pairs'], current['steps']
            if sum(ops.values()) != steps or sum(pairs.values()) != steps-1:
                raise ValueError('census totals do not conserve instruction/transition counts')
            for a, b in pairs:
                # A transition can refer only to an observed opcode from this invocation.
                if a not in ops or b not in ops:
                    raise ValueError('unobserved census pair endpoint')
            for opcode, count in ops.items():
                # Exactly one start/end deficit is permitted across the full invocation, including host resumptions.
                outgoing = sum(n for (a, _), n in pairs.items() if a == opcode)
                incoming = sum(n for (_, b), n in pairs.items() if b == opcode)
                if count-outgoing not in (0, 1) or count-incoming not in (0, 1):
                    raise ValueError('inconsistent census endpoints')
            seen, pending = set(), [next(iter(ops))]
            while pending:
                # Conservation alone permits a disconnected cycle plus an isolated endpoint; a real invocation is one connected walk.
                node = pending.pop()
                if node not in seen:
                    seen.add(node)
                    pending.extend(b for a, b in pairs if a == node and b not in seen)
                    pending.extend(a for a, b in pairs if b == node and a not in seen)
            if seen != set(ops):
                raise ValueError('disconnected census transitions')
            reports.append(dict(steps=steps, opcodes={str(k): ops[k] for k in sorted(ops)},
                pairs=[dict(first=a, second=b, count=pairs[a, b]) for a, b in sorted(pairs)]))
            current = None
        else:
            raise ValueError('invalid census framing')
    if current is not None:
        raise ValueError('incomplete census invocation')
    return reports, '\n'.join(regular)+('\n' if regular else '')


def calibration_passed(result, capacity=False):
    """Check fresh/nested/terminal boundaries or the exact no-partial-result saturation failure."""
    if capacity:
        return (result['exit_code'] != 0 and '[Assertion Failure]' in result['output']
                and 'opcode census pair capacity exceeded' in result['output']
                and 'census,begin,' not in result['output'])
    if result['exit_code']:
        return False
    small = dict(steps=3, opcodes={'0': 1, '2': 2},
                 pairs=[dict(first=2, second=0, count=1), dict(first=2, second=2, count=1)])
    outer = dict(steps=2, opcodes={'10': 1, '50': 1}, pairs=[dict(first=10, second=50, count=1)])
    terminal = dict(steps=1, opcodes={'10': 1}, pairs=[])
    try:
        reports, regular = parse_reports(result['output'])
    except ValueError:
        return False
    return (regular.strip() == 'PVM opcode census controls passed'
            and reports == [small, small, small, outer, small, outer, terminal, terminal])


def snapshot_sources(folder, extra_paths=(), pair_capacity=512):
    """Copy only owned inputs to an ignored snapshot and instrument its step module, retaining both source identities."""
    original, generated = {}, {}
    paths = [*sorted((ROOT/'src/pvm').rglob('*.nim')), ROOT/'src/codec/natural.nim',
             ROOT/'tests/performance/pvm_workload.nim', ROOT/'tests/support/pvm_census_control.nim', *extra_paths]
    for source in paths:
        # No production path is ever written; imported modules retain their original relative layout.
        relative = source.relative_to(ROOT)
        target = folder/relative
        target.parent.mkdir(parents=True, exist_ok=True)
        data = source.read_bytes()
        original[str(relative)] = hashlib.sha256(data).hexdigest()
        if relative.as_posix() == 'src/pvm/step.nim':
            data = instrument_step(data.decode(), pair_capacity).encode()
        target.write_bytes(data)
        generated[str(relative)] = hashlib.sha256(data).hexdigest()
    return original, generated


def build(checks, compiler, source, name, defines=(), cflags=()):
    """Retain checked native flags; a build failure cannot supply a fallback executable or partial report."""
    row, binary = checks.build(compiler, source, name, defines=defines, cflags=cflags)
    output = row.pop('output')
    (checks.folder/(name+'-build.log')).write_text(output)
    if row['exit_code'] or 'Error:' in output or 'FAILURE' in output:
        raise RuntimeError('checked PVM build failed: '+name)
    row['binary_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
    return row, binary


def calibrate(checks, compiler, snapshot, builds, controls):
    """Require compiled ordinary refusal, complete nested/host controls and explicit capacity refusal."""
    row, plain = build(checks, compiler, ROOT/'tests/support/pvm_census_control.nim', 'uninstrumented-control')
    builds.append(row)
    missing = checks.command([plain], 'control-uninstrumented',
        environment=dict(os.environ, RAGNAROK_PVM_CENSUS_CONTROL='positive'), timeout=30)
    passed = (missing['exit_code'] != 0 and '[Assertion Failure]' in missing['output']
        and 'opcode census control requires instrumented snapshot' in missing['output']
        and 'census,begin,' not in missing['output'])
    missing.pop('output')
    controls.append(dict(mode='uninstrumented', passed=passed, run=missing))
    if not passed:
        raise RuntimeError('uninstrumented opcode census control did not refuse')
    row, control = build(checks, compiler, snapshot/'tests/support/pvm_census_control.nim', 'control', ('pvmOpcodeCensus',))
    builds.append(row)
    for mode in ('positive', 'capacity'):
        # The positive control proves invocation reset/nesting and both host terminal paths before capacity refusal is trusted.
        result = checks.command([control], 'control-'+mode,
            environment=dict(os.environ, RAGNAROK_PVM_CENSUS_CONTROL=mode), timeout=30)
        passed = calibration_passed(result, mode == 'capacity')
        result.pop('output')
        controls.append(dict(mode=mode, passed=passed, run=result))
        if not passed:
            raise RuntimeError('opcode census calibration failed: '+mode)


def main():
    """Calibrate ignored-source instrumentation, then require identical validated counts across all policies/samples."""
    folder = ROOT/'build/tests/pvm-census'
    folder.mkdir(parents=True, exist_ok=True)
    report = folder/'results.json'
    report.unlink(missing_ok=True)
    harness = {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in
        ('tools/pvm_opcode_census.py', 'tools/native_checks.py', 'tools/pvm_benchmark_report.py')}
    variable, fixture, files = load_fixture_contracts(ROOT/'tests/fixtures')['pvm_benchmark']
    for path, expected in files:
        # The maintained frozen corpus is mandatory, including every member in its discovered contract.
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('changed opcode census fixture: '+path.name)
    original, generated = snapshot_sources(folder/'snapshot')
    checks = NativeChecks(folder, reuse_builds=True)
    compiler, _ = installed()
    builds, controls, runs = [], [], []
    calibrate(checks, compiler, folder/'snapshot', builds, controls)
    binaries = {}
    for name, defines in (('legacy', ('pvmOpcodeCensus',)), ('memo', ('pvmOpcodeCensus', 'pvmBenchmarkMemo'))):
        row, binary = build(checks, compiler, folder/'snapshot/tests/performance/pvm_workload.nim', name, defines)
        builds.append(row)
        binaries[name] = binary
    programs = {}
    for mode, engine in (('dynamic', 'ragnarok'), ('planned', 'ragnarok_planned'), ('memo', 'ragnarok_memo')):
        # Instrumented time/preparation values are parsed only to retain the existing complete native-output contract, then discarded.
        result = checks.command([binaries['memo' if mode == 'memo' else 'legacy']], 'workloads-'+mode,
            environment={**os.environ, variable: str(fixture), 'RAGNAROK_PVM_PRICING': mode}, timeout=180)
        if result['exit_code']:
            raise RuntimeError('opcode census workload failed: '+mode)
        reports, regular = parse_reports(result['output'])
        parse_output(regular, engine)
        labels = [tuple(map(int, line.split('\t')[1:3])) for line in regular.splitlines() if line.startswith('sample\t')]
        if labels != [(i, sample) for i in range(len(NAMES)) for sample in range(13)] or len(reports) != len(labels):
            raise ValueError('incomplete or reordered opcode census samples')
        for i, name in enumerate(NAMES):
            samples = reports[i*13:(i+1)*13]
            if any(item != samples[0] for item in samples) or samples[0]['steps'] != EXPECTED_STEPS[name]:
                raise ValueError('inconsistent opcode census samples: '+name)
            if name in programs and programs[name] != samples[0]:
                raise ValueError('pricing policy changed opcode/pair census: '+name)
            programs[name] = samples[0]
        result.pop('output')
        runs.append(dict(mode=mode, run=result, validated_invocations=len(reports)))
    for relative, expected in {**original, **harness}.items():
        # Concurrent source changes invalidate the run rather than mislabeling a snapshot as the current production tree.
        if hashlib.sha256((ROOT/relative).read_bytes()).hexdigest() != expected:
            raise ValueError('source changed during opcode census: '+relative)
    for path, expected in files:
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('fixture changed during opcode census: '+path.name)
    report.write_text(json.dumps(dict(diagnostic_only=True, instrumented_sample_timings_discarded=True,
        harness_sha256=harness,
        source_sha256=original, snapshot_sha256=generated, fixture_sha256={str(p.relative_to(ROOT)): h for p, h in files},
        builds=builds, controls=controls, runs=runs, programs=programs), indent=2)+'\n')
    print('PASS diagnostic opcode census: 11 workloads, 429 validated invocations; benchmark timings discarded')
    for name in NAMES:
        print(name, programs[name]['steps'], 'PVM instructions;', len(programs[name]['pairs']), 'distinct pairs')


# Pure transformation/parsing helpers do no I/O or execution when imported by harness tests.
if __name__ == '__main__':
    main()
