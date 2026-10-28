#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""CI-only calibrated invocation profiles of sealed x86 application images; clocks are discarded.

The complete thirteen-call state-checked process is retained. Return dumps separate cold work
from the final reused invocation, including private memory construction and immutable publication.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

from native_checks import NativeChecks, ROOT
from pvm_arm64_jit_applications import parse_run
from pvm_guest_compare import unchanged
from pvm_instruction_profile import calibrate_scope, collect, profile_counts
from pvm_native_ci import host_identity

BUILD = ROOT/'build/tests/pvm-x86-profiles'
COHORT = ROOT/'build/tests/pvm-x86-applications'


def selected_symbol(output, prefix):
    """One actual text definition certifies the exact scope; absent or ambiguous symbols refuse collection."""
    symbols = [fields[2] for line in output.splitlines()
               if len(fields := line.split()) == 3 and fields[1] in ('T', 't')
               and re.fullmatch(prefix+r'_[A-Za-z0-9_.]+', fields[2])]
    if len(symbols) != 1:
        raise ValueError('Missing or ambiguous public invocation symbol: '+prefix)
    return symbols[0]


def profile_environment(case, limit, role):
    """Freeze exactly the maintained complete-state workload; only the current native policy varies."""
    doom = case == 'tick'
    prepared = ROOT/'build/tests/pvm-doom/prepared'
    env = dict(os.environ, RAGNAROK_PVM_GUEST=case, RAGNAROK_PVM_BACKEND=role,
        RAGNAROK_PVM_PRICING='prepared', RAGNAROK_PVM_SIEVE_SAMPLES='13',
        RAGNAROK_PVM_SIEVE_CLOCK='1', RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0',
        RAGNAROK_PVM_DOOM_PRICING='prepared', RAGNAROK_PVM_DOOM_PREPARATION='1',
        RAGNAROK_PVM_DOOM_TIMING='1', RAGNAROK_PVM_DOOM_ASSERT='0',
        RAGNAROK_PVM_LOCAL_ONECALL='0', RAGNAROK_PVM_DOOM_PHASE=case,
        RAGNAROK_PVM_DOOM_LIFECYCLE='0', RAGNAROK_PVM_DOOM_INPUT=str(prepared),
        RAGNAROK_PVM_DOOM_ROM=str(ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad'))
    if not doom:
        # The original reference-prepared bytes, not reconstructed inputs, bind both policy profiles.
        inputs = COHORT/'inputs'/case/str(limit)
        env.update(RAGNAROK_PVM_SIEVE_INPUT=str(inputs/f'input-{limit}.bin'),
                   RAGNAROK_PVM_SIEVE_EXPECTED=str(inputs/f'expected-{limit}.bin'))
    return env


def exclusive_costs(text):
    """Sum actual instruction rows, excluding every call-arc cost even when a synthetic ancestry arc has zero calls."""
    totals = profile_counts(text)
    if re.findall(r'^positions: (.+)$', text, re.M) != ['line']:
        raise ValueError('Unsupported profile positions')
    names = list(totals)
    own = {}
    symbol, arc = '', False
    for line in text.splitlines():
        # Function headers name self rows; an immediately following arc cost belongs to its callee instead.
        if line.startswith('fn='):
            if arc: raise ValueError('Incomplete call arc')
            symbol = line[3:]
        elif line.startswith('calls='):
            if arc: raise ValueError('Incomplete call arc')
            arc = True
        elif re.match(r'^(?:[0-9]+|[+-][0-9]+|\*) ', line):
            if not symbol: raise ValueError('Instruction cost lacks a function')
            raw = line.split()[1:]
            if not raw or len(raw) > len(names) or any(re.fullmatch(r'[0-9]+', value) is None for value in raw):
                raise ValueError('Invalid instruction event row')
            values = [*map(int, raw), *([0]*(len(names)-len(raw)))]
            if not arc:
                # Include each actual event exactly once; inherited zero-call ancestry is never self work.
                costs = own.setdefault(symbol, dict.fromkeys(names, 0))
                for name, value in zip(names, values): costs[name] += value
            arc = False
    if arc or any(sum(row[name] for row in own.values()) != totals[name] for name in names):
        raise ValueError('Exclusive instruction costs do not match complete profile totals')
    return dict(sorted(own.items(), key=lambda pair: pair[1]['Ir'], reverse=True))


def matching_native_activity(measured, profiled):
    """Instrumentation must retain actual native execution and its exact code working set; only clocks may differ."""
    fields = ('fragments', 'calls', 'operations', 'code_bytes', 'branches', 'headers')
    if any(measured[key] != profiled[key] for key in fields):
        raise ValueError('Profile changed native execution or code working set')


def run():
    """Calibrate exact scope and last-return selection, profile unchanged images and retain partial failure receipts."""
    BUILD.mkdir(parents=True, exist_ok=True)
    destination = BUILD/'results.json'
    report = dict(status='incomplete', profiles=[], controls=[], builds=[],
                  hardware_counters=False, clock_policy='discarded',
                  scope='public invocation including memory construction and immutable publication')
    destination.write_text(json.dumps(report, indent=2)+'\n')
    try:
        # A local machine is never a fallback for the native Linux measurement runner.
        if os.environ.get('GITHUB_ACTIONS') != 'true':
            raise RuntimeError('x86 profiles are CI-only')
        host = host_identity()
        if host['system'] != 'Linux' or host['architecture'] != 'x86_64':
            raise RuntimeError('Profiles require native Linux x86-64')
        cohort_path = COHORT/'results.json'
        cohort = json.loads(cohort_path.read_text())
        if cohort['status'] != 'passed' or cohort['architecture'] != 'x86_64':
            raise ValueError('Missing complete x86 application cohort')
        head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        if cohort['revision'] != head:
            raise ValueError('Profile and measured cohort heads differ')
        identities = {ROOT/name: value for name, value in cohort['identities'].items()}
        unchanged(identities)
        report.update(revision=head, cpu=cohort['cpu'], compiler_identity=cohort['compiler_identity'],
                      cohort_sha256=hashlib.sha256(cohort_path.read_bytes()).hexdigest(),
                      identities=cohort['identities'])
        checks = NativeChecks(BUILD)
        version = checks.command(['valgrind', '--version'], 'version')
        if version['exit_code'] or re.fullmatch(r'valgrind-[0-9]+\.[0-9]+\.[0-9]+\s*', version['output']) is None:
            raise ValueError('Invalid Valgrind version')
        report['valgrind'] = version['output'].strip()
        calibrate_scope(checks, report)
        for case, limit in (('sieve', 100000), ('pinky', 1), ('tick', 0)):
            # Short sieve exercises the same loop boundary at a bounded profiling cost; no profiled clock is a timing.
            for role in ('interpreter', 'jit'):
                row = next(r for r in cohort['runs'] if
                    (r['case'], r['limit'], r['role'], r['order']) == (case, limit, role, 0))
                binary = Path(row['run']['command'][0])
                symbols = checks.command(['nm', '--defined-only', binary], case+'-'+role+'-symbols')
                if symbols['exit_code']:
                    raise RuntimeError('Cannot inspect public invocation image')
                scope = selected_symbol(symbols['output'], 'runPreparedDoom' if case == 'tick' else 'runPreparedKernel')
                name = case+'-'+role
                unchanged(identities)
                executed, final = collect(checks, binary, name, scope,
                    profile_environment(case, limit, 'interpreted' if role == 'interpreter' else 'jit'),
                    1200, dump_symbols=(scope,), executions=13)
                if executed['exit_code']:
                    raise RuntimeError('Profile process failed: '+name)
                events = (ROOT/'build/tests/pvm-doom/prepared/tick.events').stat().st_size if case == 'tick' else 0
                parsed = parse_run(executed['output'], role, case, limit, events, cohort['comparison_protocol'])
                matching_native_activity(row['parsed']['native'], parsed['native'])
                if len(parsed['execution']['samples']) != 13:
                    raise ValueError('Incomplete checked profile calls')
                cold = final.parent/(name+'.callgrind.1')
                cold_counts, warm_counts = profile_counts(cold.read_text()), profile_counts(final.read_text())
                own = exclusive_costs(final.read_text())
                annotation = checks.command(['callgrind_annotate', '--auto=no', '--inclusive=no',
                    '--threshold=99', '--show=Ir,Bc,Bcm,Bi,Bim', final], name+'-self')
                arcs = checks.command(['callgrind_annotate', '--auto=no', '--inclusive=yes',
                    '--tree=both', '--threshold=95', '--show=Ir', final], name+'-arcs')
                if annotation['exit_code'] or arcs['exit_code']:
                    raise RuntimeError('Profile annotation failed: '+name)
                hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sorted(BUILD.glob(name+'.callgrind*'))}
                report['profiles'].append(dict(case=case, role=role, scope=scope,
                    checked_calls=13, cold=cold_counts, reused=warm_counts, self_costs=own,
                    run={k:v for k,v in executed.items() if k != 'output'},
                    profile_hashes=hashes, native=parsed['native']))
                # Preserve both independently parsed cold and reused raw dumps; intermediate complete warmups need only seals.
                for index in range(2, 13):
                    (BUILD/(name+'.callgrind.'+str(index))).unlink()
                unchanged(identities)
                destination.write_text(json.dumps(report, indent=2)+'\n')
                print(name, 'cold Ir', cold_counts['Ir'], 'reused Ir', warm_counts['Ir'], flush=True)
        report['status'] = 'passed'
    except Exception as error:
        # Any absent scope, incomplete output or changed image leaves an explicit failed receipt and the original diagnostic.
        report.update(status='failed', error=str(error))
        raise
    finally:
        destination.write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    run()
