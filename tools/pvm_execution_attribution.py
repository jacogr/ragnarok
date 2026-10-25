#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Attribute checked execution to native inline functions, generated C lines and call edges.

Diagnostic debug information preserves the checked optimized profile. Instrumented clocks
are discarded, unmapped costs remain explicit and inclusive call costs never enter self totals.
"""
from collections import Counter
import json
import os
from pathlib import Path
import platform
import re
import shutil

from native_checks import NativeChecks, ROOT
from pvm_guest_compare import DRIVER, snapshot, working_paths
from pvm_guest_compare import summarize as validate_comparison
from pvm_guest_inputs import digest, prepare_inputs
from pvm_instruction_profile import (VERSION, calibrate_scope, capture_generated_sources,
                                     collect, profile_counts, verify_generated_sources)
from pvm_interpreter_diagnosis import incoming_entries
from pvm_opcode_census import build
from pvm_sieve_report import parse_process_output
from setup_nimony import installed


BUILD = ROOT/'build/tests/pvm-execution-attribution'
CASES = (('pinky', 1), ('memset', 100000), ('minimal', 100000))


def attribution(text):
    """Reconcile absolute native/source positions and separate call-edge totals from exclusive work."""
    counts = profile_counts(text)
    if re.findall(r'^positions: (.+)$', text, re.M) != ['instr line']:
        raise ValueError('attribution requires instruction and line positions')
    file, function, callee, call = None, None, None, None
    lines, functions, edges = Counter(), Counter(), []
    for row in text.splitlines():
        # fl/fi/fe all change the current cost file; cfi/cfl identify callees only.
        if row.startswith(('fl=', 'fi=', 'fe=')):
            file = row[3:]
        elif row.startswith('fn='):
            function, callee = row[3:], None
        elif row.startswith('cfn='):
            callee = row[4:]
        elif row.startswith('calls='):
            call = int(row[6:].split()[0])
        elif row and row[0] in '0123456789+-*':
            values = row.split()
            if len(values) < 3 or not re.fullmatch(r'(?:0x[0-9a-f]+|[0-9]+)', values[0]) \
                    or not values[1].isdecimal():
                raise ValueError('compressed or incomplete source position')
            cost, line = int(values[2]), int(values[1])
            if call is not None:
                if callee is None:
                    raise ValueError('call cost lacks callee identity')
                edges.append(dict(caller=function, callee=callee, calls=call, inclusive_ir=cost,
                                  file=file, line=line))
                call = None
            else:
                if function is None or file is None:
                    raise ValueError('self cost lacks source/function identity')
                functions[function] += cost
                lines[file, line, function] += cost
    if call is not None or sum(functions.values()) != counts['Ir']:
        raise ValueError('exclusive attribution does not reconcile to complete instruction total')
    return dict(counts=counts, functions=functions.most_common(), calls=edges,
                lines=[dict(file=f, line=n, function=fn, ir=cost)
                       for (f, n, fn), cost in lines.most_common()])


def run():
    """Freeze production sources and complete inputs, then retain exact line/inline/call evidence for both engines."""
    BUILD.mkdir(parents=True, exist_ok=True)
    for name in ('results.json', 'partial.json', 'summary.md'):
        (BUILD/name).unlink(missing_ok=True) # Failure must not leave a previous completed diagnosis.
    report = dict(status='running', builds=[], controls=[], profiles=[],
                  clock_policy='Instrumented clocks discarded; native instruction shares are not CPU-time shares.')
    try:
        if platform.system() != 'Linux' or platform.machine() != 'x86_64':
            raise RuntimeError('deep attribution requires Linux x86-64 CI')
        checks = NativeChecks(BUILD)
        head = checks.command(['git', 'rev-parse', 'HEAD'], 'head')['output'].strip()
        identity = json.loads((BUILD.parent/'pvm-build-identity/results.json').read_text())
        control = json.loads((BUILD.parent/'pvm-guest-compare/results.json').read_text())
        validate_comparison(control)
        pairs = [row for row in identity['pairs'] if row['policy'] == 'canonical-paths']
        if identity['status'] != 'checks-passed' or identity['head'] != head \
                or len(pairs) != 3 or not all(row['identical'] for row in pairs) \
                or control['candidate_head_context'] != head or not control['identical_sources']:
            raise RuntimeError('missing current-head strict image controls before attribution')
        report.update(head=head, identity_control='three canonical stress pairs pass',
                      comparison_validated_invocations=control['validated_invocations'])
        version = checks.command(['valgrind', '--version'], 'version')
        if version['exit_code'] or version['output'].strip() != VERSION:
            raise RuntimeError('unexpected Callgrind version')
        calibrate_scope(checks, report)
        members = working_paths()
        identities = {ROOT/p: digest(ROOT/p) for p in members+list(DRIVER)}
        prepared = prepare_inputs(checks, BUILD)
        identities.update(prepared['identities'])
        source = BUILD/'snapshot'
        captured = snapshot(source, None, {p: (ROOT/p).read_bytes() for p in DRIVER})
        identities.update({source/p: value for p, value in captured.items()})
        compiler, _ = installed()
        row, native = build(checks, compiler, source/DRIVER[0], 'guest',
                            cflags=('-g', '-I'+str(source/'tests/performance')))
        report['builds'].append(row)
        archive, generated = capture_generated_sources(BUILD, ROOT)
        report.update(generated_sources=generated, provenance=prepared['provenance'],
                      diagnostic_difference='native Clang -g and inline debug decoding; runtime sources/driver/checks unchanged')
        reference = prepared['reference']
        images = dict(native=native, reference=reference)
        image_hashes = {k: digest(p) for k, p in images.items()}
        report['binary_sha256'] = image_hashes
        inputs = {(g, n): (data, expected) for g, n, data, expected in prepared['inputs']}
        from native_fixture_contracts import load_fixture_contracts
        contracts = load_fixture_contracts(ROOT/'tests/fixtures')
        for engine, binary in images.items():
            symbols = checks.command(['nm', '--defined-only', binary], engine+'-symbols')
            names = re.findall(r'^[0-9a-f]+\s+[Tt]\s+(\S+)$', symbols['output'], re.M)
            selected = [n for n in names if (re.fullmatch(r'execute_[0-9]+_\w+', n) if engine == 'native'
                        else 'InterpretedInstance' in n and 'run_impl' in n)]
            if symbols['exit_code'] or not selected:
                raise RuntimeError('missing native execution scope')
            checks.command(['objdump', '-dl', '--no-show-raw-insn', binary], engine+'-assembly', timeout=90)
            for guest, limit in CASES:
                data, expected = inputs[guest, limit]
                environment = dict(os.environ, RAGNAROK_PVM_GUEST=guest,
                    RAGNAROK_PVM_PRICING='planned', RAGNAROK_PVM_SIEVE_INPUT=str(data),
                    RAGNAROK_PVM_SIEVE_EXPECTED=str(expected), RAGNAROK_PVM_SIEVE_SAMPLES='1',
                    RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0')
                args = ()
                if engine == 'reference':
                    family = 'pvm_pinky' if guest == 'pinky' else 'pvm_guests'
                    args = ('--sieve', str(contracts[family][1]/(guest+'.polkavm')), str(data.parent), str(limit), '1')
                probe_env = dict(environment, RAGNAROK_PVM_SIEVE_ASSERT_PROBE='1')
                probe = checks.command([binary, *args], engine+'-'+guest+'-assertions', environment=probe_env)
                needle = 'pvm sieve '+('native' if engine == 'native' else 'reference')+' assertion control'
                passed = probe['exit_code'] != 0 and needle in probe['output']
                probe.pop('output')
                report['controls'].append(dict(name=engine+'-'+guest+'-assertions', passed=passed, run=probe))
                if not passed:
                    raise RuntimeError('attribution assertion control failed')
                name = engine+'-'+guest
                returns = 2 if engine == 'reference' and guest == 'pinky' else 1
                scope = '*InterpretedInstance*run_impl*' if engine == 'reference' else 'execute_?_*'
                print('ATTRIBUTION '+name, flush=True)
                result, raw = collect(checks, binary, name, scope, environment, 1200,
                    instructions=True, dump_symbols=selected, executions=returns, arguments=args, deep=True)
                if result['exit_code']:
                    raise RuntimeError('attribution guest failed: '+name)
                parse_process_output(result['output'], 'ragnarok_planned' if engine == 'native'
                                     else 'polkavm_interpreter', limit, guest, samples=1)
                text = raw.read_text()
                if incoming_entries(text, selected) != 1:
                    raise RuntimeError('selected attribution has unexpected execution entry count')
                attributed = attribution(text)
                result.pop('output')
                report['profiles'].append(dict(engine=engine, guest=guest, state_checked=True,
                    raw=raw.name, raw_sha256=digest(raw), attribution=attributed, run=result))
                (BUILD/'partial.json').write_text(json.dumps(report, indent=2)+'\n')
        # Preserve the pinned reference source files named by DWARF, not guessed line mappings.
        reference_sources = {}
        for path in sorted((ROOT/'vendor/polkavm/crates').rglob('*.rs')):
            relative = path.relative_to(ROOT)
            target = BUILD/'reference-source'/relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
            reference_sources[str(relative)] = digest(path)
        report['reference_sources'] = reference_sources
        verify_generated_sources(generated, ROOT, archive)
        if members != working_paths() or any(digest(p) != h for p, h in identities.items()) \
                or image_hashes != {k: digest(p) for k, p in images.items()}:
            raise RuntimeError('attribution source/input/image identity changed')
        report.update(status='checks-passed', source_sha256={str(p.relative_to(ROOT)): h for p, h in identities.items()})
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
        lines = ['Deep checked interpreter attribution', '', report['clock_policy'], '']
        for row in report['profiles']:
            lines.append(row['engine']+' '+row['guest']+': '+str(row['attribution']['counts']['Ir'])+' instructions')
        (BUILD/'summary.md').write_text('\n'.join(lines)+'\n')
    except Exception as error:
        report.update(status='failed', error=str(error))
        (BUILD/'partial.json').write_text(json.dumps(report, indent=2)+'\n')
        raise


if __name__ == '__main__':
    run() # Parsing imported profiles never provisions dependencies or executes a guest.
