#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare pinned interpreters on complete checked guest states; diagnose without runtime edits.

Make provisions both toolchains. Native counters cover execution only, with every raw return
dump retained. Uninstrumented observations use the same executables in opposite process orders.
"""
import json
import os
from pathlib import Path
import platform
import re

from native_checks import NativeChecks, ROOT
from native_fixture_contracts import load_fixture_contracts
from pvm_benchmark import cpu_model
from pvm_guest_compare import DRIVER, snapshot, working_paths
from pvm_guest_inputs import digest, prepare_inputs
from pvm_instruction_profile import VERSION, calibrate_scope, profile_counts
from pvm_opcode_census import build
from pvm_sieve_report import parse_process_output
from setup_nimony import installed


BUILD = ROOT/'build/tests/pvm-interpreter-diagnosis'
CASES = (('pinky', 1), ('memset', 100000), ('minimal', 100000))
MODES = ('planned', 'memo', 'reference')


def self_costs(text):
    """Sum instruction self costs only; inclusive call-edge costs cannot be counted twice."""
    counts = profile_counts(text)
    if re.findall(r'^positions: (.+)$', text, re.M) != ['instr line']:
        raise ValueError('diagnosis requires uncompressed instruction/line positions')
    current, edge, costs = None, False, {}
    for line in text.splitlines():
        # String compression is disabled during collection; function names are literal identities.
        if line.startswith('fn='):
            current = line[3:]
        elif line.startswith('calls='):
            edge = True
        elif line and line[0] in '0123456789+-*':
            values = line.split()
            if len(values) >= 3:
                value = int(values[2])
                if not edge:
                    if current is None:
                        raise ValueError('instruction cost lacks function identity')
                    costs[current] = costs.get(current, 0)+value
                edge = False
    if edge or sum(costs.values()) != counts['Ir']:
        raise ValueError('function self costs do not reconcile to complete instruction total')
    return sorted(costs.items(), key=lambda item: (-item[1], item[0]))


def incoming_entries(text, symbols):
    """Require a single selected invocation, excluding zero-count ancestor call edges."""
    callee, entries = None, 0
    for line in text.splitlines():
        # The next call record belongs only to its immediately declared callee.
        if line.startswith('cfn='):
            callee = line[4:]
        elif line.startswith('fn='):
            callee = None
        elif line.startswith('calls='):
            if callee in symbols:
                entries += int(line[6:].split()[0])
            callee = None
    return entries


def return_parts(output, expected):
    """Validate every complete return, including reference initialization, then its empty termination."""
    parts = {p.name: p for p in output.parent.glob(output.name+'.*')}
    names = {output.name+'.'+str(index) for index in range(1, expected+1)}
    if set(parts) != names or profile_counts(output.read_text(), allow_empty=True)['Ir'] != 0:
        raise ValueError('unexpected return count or nonempty termination dump')
    ordered = [parts[output.name+'.'+str(index)] for index in range(1, expected+1)]
    for part in ordered:
        # Partial initialization or warmup evidence also refuses the final diagnostic.
        profile_counts(part.read_text())
    return ordered


def checked(checks, args, name, environment=None, timeout=180):
    """Persist classified command evidence, refusing a failed build/process before interpretation."""
    result = checks.command(args, name, environment=environment, timeout=timeout)
    if result['exit_code']:
        raise RuntimeError('diagnostic command failed: '+result['log'])
    return result


def run():
    """Freeze merged sources and fixtures, measure both orders, then collect calibrated native scopes."""
    BUILD.mkdir(parents=True, exist_ok=True)
    for name in ('results.json', 'partial.json', 'summary.md'):
        # A refused invocation cannot leave an earlier completed diagnosis visible.
        (BUILD/name).unlink(missing_ok=True)
    report = dict(status='running', builds=[], controls=[], profiles=[], timings=[],
                  clock_policy='Only uninstrumented driver clocks are timings; instruction shares are not CPU-time shares.')
    try:
        if platform.system() != 'Linux' or platform.machine() != 'x86_64':
            raise RuntimeError('diagnosis requires Linux x86-64 CI')
        checks = NativeChecks(BUILD)
        version = checked(checks, ['valgrind', '--version'], 'version')
        if version['output'].strip() != VERSION:
            raise RuntimeError('unexpected Valgrind version')
        report.update(cpu=cpu_model(), platform=platform.platform(), valgrind=VERSION)
        report['head'] = checked(checks, ['git', 'rev-parse', 'HEAD'], 'head')['output'].strip()
        paths = working_paths()
        identities = {ROOT/p: digest(ROOT/p) for p in paths+list(DRIVER)}
        identities.update({p: digest(p) for p in (ROOT/'tools').glob('pvm_*.py')})
        calibrate_scope(checks, report)
        prepared = prepare_inputs(checks, BUILD)
        identities.update(prepared['identities'])
        report.update(provenance=prepared['provenance'], preparations=prepared['preparations'])
        frozen = BUILD/'snapshot'
        captured = snapshot(frozen, None, {p: (ROOT/p).read_bytes() for p in DRIVER})
        identities.update({frozen/p: value for p, value in captured.items()})
        compiler, _ = installed()
        row, native = build(checks, compiler, frozen/'tests/performance/pvm_sieve.nim', 'native',
                            cflags=('-I'+str(frozen/'tests/performance'),))
        report['builds'].append(row)
        reference = prepared['reference']
        binaries = dict(planned=native, memo=native, reference=reference)
        binary_hashes = {mode: digest(binary) for mode, binary in binaries.items()}
        report['binary_sha256'] = binary_hashes
        contracts = load_fixture_contracts(ROOT/'tests/fixtures')
        inputs = {(g, n): (data, expected) for g, n, data, expected in prepared['inputs']}

        def invocation(guest, limit, mode, samples):
            """Use the unchanged maintained drivers and the same pinned complete expected state."""
            data, expected = inputs[guest, limit]
            environment = dict(os.environ, RAGNAROK_PVM_GUEST=guest,
                RAGNAROK_PVM_PRICING=mode, RAGNAROK_PVM_SIEVE_INPUT=str(data),
                RAGNAROK_PVM_SIEVE_EXPECTED=str(expected), RAGNAROK_PVM_SIEVE_SAMPLES=str(samples),
                RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0')
            arguments = [str(binaries[mode])]
            if mode == 'reference':
                family = 'pvm_pinky' if guest == 'pinky' else 'pvm_guests'
                artifact = contracts[family][1]/(guest+'.polkavm')
                arguments += ['--sieve', str(artifact), str(data.parent), str(limit), str(samples)]
            return arguments, environment

        def parse(result, guest, limit, mode, samples):
            """A zero exit alone cannot certify final state, mode, preparation or complete sample framing."""
            engine = 'polkavm_interpreter' if mode == 'reference' else 'ragnarok_'+mode
            return parse_process_output(result['output'], engine, limit, guest, samples=samples)

        for mode in ('planned', 'reference'):
            # Both independent drivers must retain their explicit assertion-refusal controls.
            args, env = invocation('pinky', 1, mode, 1)
            env['RAGNAROK_PVM_SIEVE_ASSERT_PROBE'] = '1'
            result = checks.command(args, mode+'-assertions', environment=env)
            needle = 'pvm sieve '+('reference' if mode == 'reference' else 'native')+' assertion control'
            passed = result['exit_code'] != 0 and needle in result['output']
            result.pop('output')
            report['controls'].append(dict(name=mode+'-assertions', passed=passed, run=result))
            if not passed:
                raise RuntimeError('assertion control refused diagnostic')
        for order, modes in enumerate((MODES, MODES[::-1])):
            for guest, limit in CASES:
                for mode in modes:
                    # All observations, including cold sample zero, remain available without filtering.
                    args, env = invocation(guest, limit, mode, 13)
                    result = checked(checks, args, f'timing-{order}-{guest}-{mode}', env)
                    observations = parse(result, guest, limit, mode, 13)
                    result.pop('output')
                    report['timings'].append(dict(order=order, guest=guest, mode=mode,
                                                  observations=observations, run=result))
        symbols = {}
        for mode in ('planned', 'reference'):
            raw = checked(checks, ['nm', '--defined-only', binaries[mode]], mode+'-symbols')['output']
            names = re.findall(r'^[0-9a-f]+\s+[Tt]\s+(\S+)$', raw, re.M)
            selected = [n for n in names if (re.fullmatch(r'execute_[0-9]+_\w+', n) if mode == 'planned'
                        else 'InterpretedInstance' in n and 'run_impl' in n)]
            if not selected:
                raise RuntimeError('execution symbol missing; no whole-process fallback')
            symbols[mode] = selected
            assembly = checked(checks, ['objdump', '-d', '-C', '--no-show-raw-insn', binaries[mode]],
                               mode+'-disassembly', timeout=60)
            if 'file format elf64-x86-64' not in assembly['output']:
                raise RuntimeError('native disassembly missing')
        symbols['memo'] = symbols['planned']
        report['symbols'] = symbols
        for guest, limit in CASES:
            for mode in MODES:
                # Planned is immutable/precomputed; memo and reference retain cold and final warm invocations.
                samples = 1 if mode == 'planned' else 13
                initialization = 1 if mode == 'reference' and guest == 'pinky' else 0
                total = samples+initialization
                args, env = invocation(guest, limit, mode, samples)
                name = guest+'-'+mode
                print('PROFILE '+name+' ('+str(total)+' complete returns)', flush=True)
                output = BUILD/(name+'.callgrind')
                output.unlink(missing_ok=True)
                for old in BUILD.glob(output.name+'.*'):
                    old.unlink() # Private old return parts must never satisfy a new invocation.
                scope = '*InterpretedInstance*run_impl*' if mode == 'reference' else 'execute_?_*'
                result = checked(checks, ['valgrind', '--tool=callgrind', '--demangle=no',
                    '--collect-atstart=no', '--toggle-collect='+scope, '--cache-sim=no',
                    '--branch-sim=yes', '--compress-strings=no', '--dump-instr=yes',
                    *('--dump-after='+symbol for symbol in symbols[mode]),
                    '--callgrind-out-file='+str(output), '--log-file='+str(BUILD/(name+'-valgrind.log')),
                    *args], name, env, timeout=1200)
                parse(result, guest, limit, mode, samples)
                result.pop('output')
                parts = return_parts(output, total)
                for index, part in enumerate(parts):
                    # Initialization is deliberately retained but never relabeled as a checked guest frame.
                    text = part.read_text()
                    if incoming_entries(text, symbols[mode]) != 1:
                        raise RuntimeError('unexpected selected execution entries: '+part.name)
                    costs = self_costs(text)
                    if index in (initialization, total-1):
                        report['profiles'].append(dict(guest=guest, mode=mode,
                            invocation=index-initialization, state_checked=True,
                            counts=profile_counts(text), self_costs=costs,
                            profile_file=part.name, profile_sha256=digest(part),
                            binary_sha256=binary_hashes[mode], run=result))
                (BUILD/'partial.json').write_text(json.dumps(report, indent=2)+'\n')
        for path, identity in identities.items():
            if digest(path) != identity:
                raise RuntimeError('diagnostic source/input changed: '+str(path))
        if paths != working_paths() or binary_hashes != {m: digest(b) for m, b in binaries.items()}:
            raise RuntimeError('diagnostic image or module membership changed')
        report.update(status='checks-passed', source_sha256={str(p.relative_to(ROOT)): h
                                                           for p, h in identities.items()})
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
        lines = ['Interpreter diagnosis', '', report['clock_policy'], '',
                 '| Guest | Engine/policy | Invocation | Native instructions |',
                 '| --- | --- | ---: | ---: |']
        for row in report['profiles']:
            lines.append(f"| {row['guest']} | {row['mode']} | {row['invocation']} | {row['counts']['Ir']} |")
        (BUILD/'summary.md').write_text('\n'.join(lines)+'\n')
        print('\n'.join(lines))
    except Exception as error:
        # Explicit partial evidence preserves failure without replacing it with an older result.
        report.update(status='failed', error=str(error))
        (BUILD/'partial.json').write_text(json.dumps(report, indent=2)+'\n')
        raise


if __name__ == '__main__':
    run() # Importing validation helpers never builds or profiles guests.
