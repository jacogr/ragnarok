#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Qualify lazy prepared execution with frozen guest states, cold/reused observations and optional Linux counts/timings.

Make owns setup. Local checks disable clocks. CI uses the same binary for existing and prepared paths;
these are execution-model comparisons, not a claim of binary identity with an older master image.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess

from native_checks import NativeChecks, ROOT
from pvm_guest_inputs import CASES, digest, prepare_inputs
from pvm_instruction_profile import (SCOPE, VERSION, calibrate_scope, collect,
                                     execution_entry_count, profile_counts)
from setup_nimony import installed

BUILD = ROOT/'build/tests/pvm-prepared-blocks'
MODES = ('dynamic', 'planned', 'prepared')


def integers(fields):
    """Evidence integers have one canonical nonnegative spelling, with no whitespace or floating-point fallback."""
    if any(re.fullmatch(r'0|[1-9][0-9]*', value) is None for value in fields):
        raise ValueError('noncanonical observation integer')
    return list(map(int, fields))


def parse_output(text, engine, limit, samples, guest, clocked):
    """Only exact complete output can publish sample or cache observations; unknown/partial rows fail."""
    rows, caches, preparation = [], [], []
    families = 0
    for line in text.splitlines():
        fields = line.split(',')
        if fields[0] == 'GUEST' and len(fields) == 2 and fields[1] == guest and guest != 'sieve':
            # Guest identity is also checked by the native frame/prime-count oracle.
            families += 1
            continue
        if fields[0] in ('GAS_PLAN', 'PREPARED_PROGRAM'):
            expected = 'PREPARED_PROGRAM' if engine == 'ragnarok_prepared' else 'GAS_PLAN' if engine == 'ragnarok_planned' else ''
            if fields[0] != expected or len(fields) != (5 if expected == 'PREPARED_PROGRAM' else 7):
                raise ValueError('foreign preparation metadata')
            numbers = integers(fields[1:])
            if min(numbers[2:]) <= 0 or (clocked and min(numbers[:2]) <= 0) or (not clocked and any(numbers[:2])):
                raise ValueError('invalid preparation metadata')
            preparation.append(fields)
        elif fields[0] == 'PREPARED_CACHE':
            if engine != 'ragnarok_prepared' or len(fields) != 10:
                raise ValueError('foreign cache observation')
            values = integers(fields[1:])
            if values[0] != len(caches) or min(values) < 0 or values[1] > 64*1024*1024 or values[4] < 1 or values[5] < 1:
                raise ValueError('invalid prepared cache observation')
            caches.append(values)
        elif fields[0] == 'SIEVE':
            if len(fields) != 6 or fields[1] != engine or fields[2] != str(limit) or fields[3] != str(len(rows)):
                raise ValueError('foreign or out-of-order execution sample')
            wall, cpu = integers(fields[4:])
            if (clocked and min(wall, cpu) <= 0) or (not clocked and (wall != 0 or cpu != 0)):
                raise ValueError('invalid execution clocks')
            rows.append(dict(sample=len(rows), wall_ns=wall, cpu_ns=cpu))
        else:
            raise ValueError('unknown execution output')
    if families != (0 if guest == 'sieve' else 1):
        raise ValueError('missing or repeated guest identity')
    if len(rows) != samples or (engine == 'ragnarok_prepared' and (len(caches) != samples or len(preparation) != 1 or preparation[0][0] != 'PREPARED_PROGRAM')):
        raise ValueError('incomplete execution observations')
    if engine == 'ragnarok_planned' and (len(preparation) != 1 or preparation[0][0] != 'GAS_PLAN'):
        raise ValueError('missing plan preparation')
    if engine in ('ragnarok', 'polkavm_interpreter') and preparation:
        raise ValueError('foreign preparation output')
    return dict(samples=rows, caches=caches, preparation=preparation)


def summary(report):
    """Partial runs never present successful comparison ratios."""
    if report['status'] != 'passed':
        return 'Prepared execution: '+report['status']+'. '+report.get('error', '')+'\n'
    lines = ['| Guest | Size | Order | Existing dynamic CPU | Existing planned CPU | Prepared CPU | PolkaVM interpreted CPU | Prepared / reference |',
             '|---|---:|---:|---:|---:|---:|---:|---:|'] if report['timings'] else [
             '| Guest | Size | Complete-state checks | Prepared retained bytes |', '|---|---:|---|---:|']
    for guest, limit in CASES:
        selected = [row for row in report['runs'] if row['guest'] == guest and row['limit'] == limit]
        engines = ('ragnarok', 'ragnarok_planned', 'ragnarok_prepared', 'polkavm_interpreter') if report['timings'] else ('ragnarok', 'ragnarok_planned', 'ragnarok_prepared')
        if len(selected) != len(engines)*2 or {(row['engine'],row['order']) for row in selected} != {(engine,order) for engine in engines for order in (0,1)}:
            raise ValueError('incomplete or duplicate comparison matrix')
        prepared = [row for row in selected if row['engine'] == 'ragnarok_prepared']
        if len(prepared) != 2:
            raise ValueError('missing reversed prepared passes')
        if report['timings']:
            for order in (0, 1):
                # Keep process-order medians separate so order sensitivity remains visible.
                medians = {}
                for engine in engines:
                    values = [sample['cpu_ns'] for row in selected if row['engine'] == engine and row['order'] == order for sample in row['samples'][3:]]
                    if len(values) != 10: raise ValueError('incomplete warmed samples')
                    medians[engine] = statistics.median(values)
                d, a, b, c = (medians[engine] for engine in engines)
                lines.append(f'| {guest} | {limit} | {order+1} | {d/1e6:.3f} ms | {a/1e6:.3f} ms | {b/1e6:.3f} ms | {c/1e6:.3f} ms | {b/c:.2f}× |')
        else:
            resident = max(row['caches'][-1][1] for row in prepared)
            lines.append(f'| {guest} | {limit} | passed, both orders | {resident:,} |')
    lines += ['', 'Cold execution includes lazy preparation. Constructor cost, every raw sample, cache growth and eviction are retained separately.',
              'Existing and prepared paths use the same checked candidate binary; this does not isolate unrelated code-layout effects.', '']
    return '\n'.join(lines)


def run(timings=False, counts=False):
    """Build once, validate source controls, and retain incomplete evidence on any refusal or changed input."""
    BUILD.mkdir(parents=True, exist_ok=True)
    report = dict(status='running', timings=timings, counts=counts, checks=[], builds=[], runs=[], profiles=[], controls=[])
    (BUILD/'summary.md').unlink(missing_ok=True)
    checks = NativeChecks(BUILD)

    def save():
        """Retire old success before preparation and preserve partial failure evidence."""
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')

    def command(args, name, environment, failure=None):
        """Classified assertion controls cannot pass on a generic crash or process success."""
        row = checks.command(args, name, environment=environment, timeout=900)
        text = row.pop('output')
        report['checks'].append(row)
        save()
        if failure is None and row['exit_code']:
            raise ValueError(name+' failed; see '+row['log'])
        if failure is not None and (row['exit_code'] == 0 or failure not in text):
            raise ValueError(name+' failed to preserve its assertion control')
        return text

    save()
    try:
        if (timings or counts) and (platform.system() != 'Linux' or platform.machine() != 'x86_64'):
            raise ValueError('Counters/timings require the Linux x86_64 verification runner')
        if timings and not counts:
            raise ValueError('Collect deterministic counts before the paired timing phase')
        compiler, _ = installed()
        identities = {path: digest(path) for path in [*sorted((ROOT/'src/pvm').rglob('*.nim')),
            ROOT/'tests/performance/pvm_sieve.nim', ROOT/'tests/performance/pvm_sieve_clock.h',
            Path(__file__), ROOT/'spec/toolchain.json', ROOT/'Makefile']}
        ready = prepare_inputs(checks, BUILD)
        identities.update(ready['identities'])
        reference = ready['reference']
        row, binary = checks.build(compiler, ROOT/'tests/performance/pvm_sieve.nim', 'guest',
                                   cflags=('-g', '-I'+str(ROOT/'tests/performance')))
        output = row.pop('output'); report['checks'].append(row)
        if row['exit_code'] or 'Error:' in output: raise ValueError('native guest build failed')
        identities[binary] = digest(binary)
        report.update(revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                      sources={str(path.relative_to(ROOT)): value for path, value in identities.items()},
                      compiler=json.loads((ROOT/'build/toolchain/environment.json').read_text()),
                      platform=platform.platform(), provenance=ready['provenance'], preparations=ready['preparations'])
        command([binary], 'assert-native', dict(os.environ, RAGNAROK_PVM_SIEVE_ASSERT_PROBE='1'), 'pvm sieve native assertion control')
        if counts:
            # Reuse the maintained selected/absent/repeated-scope calibration before trusting a new guest profile.
            version = command(['valgrind', '--version'], 'valgrind-version', dict(os.environ))
            if version.strip() != VERSION: raise ValueError('unexpected Valgrind version')
            calibrate_scope(checks, report)
        # Complete all selected instruction-count comparisons before beginning any timing pass.
        for guest, limit, data, expected in ready['inputs']:
            base = dict(os.environ, RAGNAROK_PVM_GUEST=guest, RAGNAROK_PVM_SIEVE_INPUT=str(data),
                        RAGNAROK_PVM_SIEVE_EXPECTED=str(expected), RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0')
            if counts and (guest, limit) in (('pinky', 1), ('sieve', 100000), ('memset', 100000), ('minimal', 100000)):
                for mode in ('planned', 'prepared'):
                    # One complete cold execution includes its own preparation; fixture construction and validation are outside scope.
                    env = dict(base, RAGNAROK_PVM_PRICING=mode, RAGNAROK_PVM_SIEVE_SAMPLES='1', RAGNAROK_PVM_SIEVE_CLOCK='0')
                    result, raw = collect(checks, binary, f'profile-{guest}-{mode}', SCOPE, env, 1800)
                    if result['exit_code']: raise ValueError('prepared profile process failed')
                    parse_output(result['output'], 'ragnarok_'+mode, limit, 1, guest, False)
                    text = raw.read_text()
                    if execution_entry_count(text) != 1: raise ValueError('profile did not collect exactly one execution')
                    report['profiles'].append(dict(guest=guest, mode=mode, events=profile_counts(text),
                        raw=str(raw.relative_to(ROOT)), sha256=digest(raw)))
                    save()
        for guest, limit, data, expected in ready['inputs']:
            base = dict(os.environ, RAGNAROK_PVM_GUEST=guest, RAGNAROK_PVM_SIEVE_INPUT=str(data),
                        RAGNAROK_PVM_SIEVE_EXPECTED=str(expected), RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0')
            artifact = ROOT/'tests/fixtures'/({'sieve':'pvm-sieve','pinky':'pvm-pinky'}.get(guest,'pvm-guests'))/(guest+'.polkavm')
            modes = (*MODES, 'reference') if timings else MODES
            for order, selected in enumerate((modes, tuple(reversed(modes)))):
                for mode in selected:
                    # Every endpoint restores exactly the same source and validates all posterior bytes/registers/gas.
                    size = 13 if timings else 1
                    env = dict(base, RAGNAROK_PVM_PRICING=mode, RAGNAROK_PVM_SIEVE_SAMPLES=str(size),
                               RAGNAROK_PVM_SIEVE_CLOCK='1' if timings else '0')
                    args = [reference, '--sieve', artifact, data.parent, limit, size] if mode == 'reference' else [binary]
                    engine = 'polkavm_interpreter' if mode == 'reference' else 'ragnarok_'+mode if mode != 'dynamic' else 'ragnarok'
                    text = command(args, f'pass-{order}-{guest}-{limit}-{mode}', env)
                    parsed = parse_output(text, engine, limit, size, guest, timings)
                    report['runs'].append(dict(guest=guest, limit=limit, order=order, engine=engine, **parsed))
                    for path, identity in identities.items():
                        # No child process may mutate captured sources, reference fixtures, binaries or expected state.
                        if digest(path) != identity: raise ValueError('changed execution identity: '+str(path))
                    save()
        report['status'] = 'passed'
        text = summary(report)
        (BUILD/'summary.md').write_text(text)
        print(text)
    except Exception as error:
        report.update(status='failed', error=str(error))
        (BUILD/'summary.md').write_text(summary(report))
        raise
    finally:
        save()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timings', action='store_true')
    parser.add_argument('--counts', action='store_true')
    args = parser.parse_args()
    run(args.timings, args.counts)
