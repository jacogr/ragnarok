#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Attribute checked Linux guest execution with calibrated Callgrind; instrumented clocks are never timings.

Make owns setup. The maintained full-state guest driver checks every selected execution, including memo warmup.
Function-scoped collection excludes input preparation and result validation without runtime hooks.
"""
import json
import os
from pathlib import Path
import platform
import re
import shutil

from native_checks import NativeChecks, ROOT
from pvm_guest_inputs import digest, prepare_inputs
from pvm_guest_compare import DRIVER, snapshot, working_paths
from pvm_opcode_census import build
from pvm_sieve_report import parse_process_output
from setup_nimony import installed


BUILD = ROOT/'build/tests/pvm-instruction-profile'
# Fixed bounded long loops expose call/return and memory costs alongside the real initialized frame.
CASES = (('pinky', 1, 'dynamic'), ('pinky', 1, 'planned'), ('sieve', 100000, 'planned'),
         ('minimal', 100000, 'planned'), ('memset', 100000, 'planned'),
         ('memset', 100000, 'memo'), ('pinky', 1, 'memo'))
VERSION = 'valgrind-3.22.0'
SCOPE = 'execute_?_*'


def profile_counts(text, allow_empty=False):
    """Require one complete instruction-count footer, not a partial dump, generic log or unrelated event column."""
    events = re.findall(r'^events: (.+)$', text, re.M)
    totals = re.findall(r'^totals: (.+)$', text, re.M)
    summaries = re.findall(r'^summary: (.+)$', text, re.M)
    if (len(events) != 1 or len(totals) != 1 or len(summaries) != 1
            or not text.startswith('# callgrind format\n')):
        raise ValueError('incomplete Callgrind profile')
    names = events[0].split()
    if not names or names[0] != 'Ir' or len(names) != len(set(names)):
        raise ValueError('invalid Callgrind events')
    rows = []
    for raw in (summaries[0], totals[0]):
        # Callgrind omits trailing zero event costs even when string/position compression is disabled.
        values = raw.split()
        if (not values or len(values) > len(names)
                or any(re.fullmatch(r'0|[1-9][0-9]*', value) is None for value in values)):
            raise ValueError('invalid Callgrind event totals')
        rows.append([*map(int, values), *([0]*(len(names)-len(values)))])
    if rows[0] != rows[1]:
        raise ValueError('Callgrind header/footer totals disagree')
    counts = dict(zip(names, rows[1]))
    if not allow_empty and counts['Ir'] == 0:
        raise ValueError('Callgrind collected no instructions')
    return counts


def exclusive_costs(text, allow_empty=False):
    """Sum actual instruction rows, excluding every call-arc cost even when a synthetic ancestry arc has zero calls."""
    totals = profile_counts(text, allow_empty=allow_empty)
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


def selected_calibration_work(text):
    """Only selected/inside self instructions may be collected; zero-self ancestry nodes are not outside work."""
    own=exclusive_costs(text)
    selected=own.get('pvm_profile_selected',{}).get('Ir',0)
    return selected > 0 and all(name in ('pvm_profile_selected','pvm_profile_inside') or row['Ir']==0
                               for name,row in own.items())


def calibration_passed(result, text, selected):
    """A matching selected function collects instructions; a deliberately absent scope collects none."""
    if result['exit_code'] or result['output'].strip() != 'PVM profile calibration passed':
        return False
    try:
        counts = profile_counts(text, allow_empty=not selected)
    except ValueError:
        return False
    try:
        return selected_calibration_work(text) if selected else (all(value==0 for value in counts.values()) and
            all(value==0 for row in exclusive_costs(text,allow_empty=True).values() for value in row.values()))
    except ValueError:
        return False


def last_call_calibration_passed(single, repeated, final):
    """Two selected calls double Ir; calibrated complete return dumps retain exactly the last selected call."""
    counts = []
    for text in (single, repeated, final):
        # Require actual selected function records, not caller references or a partial/empty dump.
        try:
            if not selected_calibration_work(text): return False
            counts.append(profile_counts(text)['Ir'])
        except ValueError:
            return False
    return counts[1] == 2*counts[0] and counts[2] == counts[0]


def execution_entry_count(text):
    """Count actual incoming selected execution calls; each complete selected dump must retain exactly one."""
    callee = None
    total = 0
    for line in text.splitlines():
        # Uncompressed names bind the next call record; unrelated functions cannot certify entry reset.
        if line.startswith('cfn='):
            callee = line[4:]
        elif line.startswith('fn='):
            callee = None
        elif line.startswith('calls=') and callee is not None:
            if re.fullmatch(r'execute_[0-9]+_\w+', callee):
                fields = line[6:].split()
                if not fields or re.fullmatch(r'0|[1-9][0-9]*', fields[0]) is None:
                    raise ValueError('invalid selected execution call count')
                total += int(fields[0])
            callee = None
    return total



def capture_generated_sources(folder, repository, cache_name="guest"):
    """Retain exact generated C at its recorded relative paths for offline source annotation."""
    if type(cache_name) is not str or re.fullmatch(r'[a-z][a-z0-9-]*', cache_name) is None:
        raise ValueError('invalid generated-source compiler cache name')
    folder, repository = Path(folder).resolve(), Path(repository).resolve()
    archive = folder/'generated-source'
    if archive.is_symlink():
        # An old archive cannot redirect new generated files outside this verification group.
        raise ValueError('generated source archive is a symlink')
    if archive.exists():
        shutil.rmtree(archive)
    archive.mkdir(parents=True)
    manifest = {}
    for source in sorted(folder.glob('compiler-*/'+cache_name+'-cache/c/**/*.c')):
        # Compiler output must remain inside this group even if a cache contains symlinks.
        if not source.resolve().is_relative_to(folder):
            raise ValueError('generated C escapes the profile build')
        relative = source.relative_to(repository).as_posix()
        destination = archive/relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        manifest[relative] = dict(bytes=source.stat().st_size, sha256=digest(source))
    if not manifest:
        raise ValueError('native generated C unavailable for source attribution')
    verify_generated_sources(manifest, repository, archive)
    return archive, manifest


def verify_generated_sources(manifest, repository, archive):
    """A changed, missing or redirected original/copy cannot certify an annotated executable."""
    repository, archive = Path(repository).resolve(), Path(archive).resolve()
    for relative, identity in manifest.items():
        path = Path(relative)
        if path.is_absolute() or '..' in path.parts:
            raise ValueError('invalid generated source identity')
        for source, boundary in [(repository/path, archive.parent), (archive/path, archive)]:
            # Validate both roots before reading; the archive alone must reproduce the original bytes.
            if (not source.is_file() or not source.resolve().is_relative_to(boundary)
                    or source.stat().st_size != identity['bytes']
                    or digest(source) != identity['sha256']):
                raise ValueError('generated source changed: '+relative)


def execution_source_files(text, manifest):
    """Bind each uncompressed selected execution symbol to one captured generated source."""
    current = None
    selected = set()
    for line in text.splitlines():
        # Calibrated collection disables string compression; never guess unknown file aliases.
        if line.startswith('fl='):
            current = line[3:]
        elif re.fullmatch(r'fn=execute_[0-9]+_\w+', line):
            if current not in manifest:
                raise ValueError('selected execution source was not captured')
            selected.add(current)
    if not selected:
        raise ValueError('profile lacks selected execution source')
    return sorted(selected)


def source_annotation_passed(result, sources):
    """Function-summary success alone is insufficient: every selected file needs a source section."""
    sections = re.findall(r'^(?:--\s*)?(?:User|Auto)-annotated source:\s*(.+)$',
                          result['output'], re.M)
    return (result['exit_code'] == 0 and 'PROGRAM TOTALS' in result['output']
            and bool(sources) and all(any(section == source or section.startswith(source+' ')
                                         for section in sections)
                                     for source in sources))


def machine_profile_counts(text, reference):
    """Instruction positions and identical selected Ir bind the extra trace to its source-level invocation."""
    positions = re.findall(r'^positions: (.+)$', text, re.M)
    if (len(positions) != 1 or len(positions[0].split()) != 2
            or set(positions[0].split()) != {'instr', 'line'}
            or re.search(r'^fn=execute_[0-9]+_\w+', text, re.M) is None):
        raise ValueError('missing native instruction positions or execution scope')
    counts = profile_counts(text)
    if counts['Ir'] != reference['Ir']:
        raise ValueError('instruction/source profile counts disagree')
    return counts


def disassembly_passed(result):
    """Require x86-64 ELF code, a selected execution symbol and actual decoded instruction rows."""
    text = result['output']
    return (result['exit_code'] == 0 and 'file format elf64-x86-64' in text
            and re.search(r'^[0-9a-f]+ <execute_[0-9]+_\w+>:$', text, re.M) is not None
            and re.search(r'^\s*[0-9a-f]+:\s+[a-z][a-z0-9]*\b', text, re.M) is not None)


def final_return_dump(output, executions):
    """Require every complete bounded function-return part and an empty final dump; retain the last raw part unchanged."""
    if type(executions) is not int or not 1 <= executions <= 13:
        raise ValueError('invalid bounded execution dump count')
    parts = {path.name: path for path in output.parent.glob(output.name+'.*')}
    expected = {output.name+'.'+str(index) for index in range(1, executions+1)}
    if set(parts) != expected:
        raise ValueError('missing or unexpected function-return dumps')
    if profile_counts(output.read_text(), allow_empty=True)['Ir'] != 0:
        raise ValueError('execution costs remain after final function-return dump')
    for part in parts.values():
        # A partial warmup dump also refuses the report, even when the final selected part is complete.
        profile_counts(part.read_text())
    return parts[output.name+'.'+str(executions)]


def collect(checks, binary, name, scope, environment, timeout, instructions=False,
            dump_symbols=(), executions=1, arguments=(), deep=False, requests=False):
    """Collect a fresh selected scope; optional complete return dumps isolate its final invocation."""
    output = checks.folder/(name+'.callgrind')
    output.unlink(missing_ok=True)
    for part in output.parent.glob(output.name+'.*'):
        # Retire every private old part before collection, never reuse counters from another invocation.
        part.unlink()
    result = checks.command(['valgrind', '--tool=callgrind', '--collect-atstart=no',
        *(['--toggle-collect='+scope] if not requests else []), '--cache-sim='+('yes' if deep else 'no'), '--branch-sim=yes',
        '--compress-strings=no', *(['--dump-instr=yes'] if instructions else []),
        *(['--read-inline-info=yes', '--compress-pos=no', '--demangle=no',
           '--I1=32768,8,64', '--D1=32768,8,64', '--LL=8388608,16,64'] if deep else []),
        *('--dump-after='+symbol for symbol in dump_symbols if not requests),
        '--callgrind-out-file='+str(output),
        '--log-file='+str(checks.folder/(name+'-valgrind.log')), binary, *arguments], name,
        environment=environment, timeout=timeout)
    if not output.is_file():
        raise RuntimeError('Callgrind did not produce a profile: '+name)
    if dump_symbols:
        # Returning raw numbered output preserves Callgrind bytes and its original dump identity.
        output = final_return_dump(output, executions)
    return result, output


def calibrate_scope(checks, report, requests=False):
    """Share classified selected/absent/repeated/return-dump controls without rebuilding a guest image."""
    control = ROOT/'tests/support/pvm_profile_control.c'
    compiled = checks.command(['clang', '-O2', '-g', '-o', str(checks.folder/'control'), *(['-DPVM_PROFILE_REQUESTS'] if requests else []), control], 'control-build')
    report['builds'].append({key: value for key, value in compiled.items() if key != 'output'})
    if compiled['exit_code']:
        raise RuntimeError('profile calibration build failed')
    selected_text = None
    for selected in (True, False):
        # The unmatched scope proves whole-process counts cannot silently substitute for selected execution.
        name = 'control-selected' if selected else 'control-absent'
        result, output = collect(checks, checks.folder/'control', name,
            'pvm_profile_selected' if selected else 'pvm_profile_missing', dict(os.environ), 30,
            arguments=('off',) if requests and not selected else (), requests=requests)
        text = output.read_text()
        if selected:
            # Preserve the single-call reference for independently repeated/reset controls.
            selected_text = text
        passed = calibration_passed(result, text, selected)
        result.pop('output')
        report['controls'].append(dict(name=name, passed=passed, run=result, profile_sha256=digest(output)))
        if not passed:
            raise RuntimeError('profile scope calibration failed: '+name)
    repeated_text = None
    for dumped in (False, True):
        # Identical selected work runs twice; complete return dumps must retain exactly one invocation.
        name = 'control-last-only' if dumped else 'control-repeated'
        result, output = collect(checks, checks.folder/'control', name, 'pvm_profile_?elected',
            dict(os.environ), 30, dump_symbols=('pvm_profile_selected',) if dumped else (), executions=2,
            arguments=('twice-dump',) if requests and dumped else ('twice',), requests=requests)
        text = output.read_text()
        passed = calibration_passed(result, text, True)
        if dumped:
            # Process success alone cannot certify that warmup costs were actually removed.
            passed = passed and last_call_calibration_passed(selected_text, repeated_text, text)
        else:
            # The unreset control proves the second invocation was present and collected.
            repeated_text = text
            passed = passed and profile_counts(text)['Ir'] == 2*profile_counts(selected_text)['Ir']
        result.pop('output')
        report['controls'].append(dict(name=name, passed=passed, run=result, profile_sha256=digest(output)))
        if not passed:
            raise RuntimeError('profile last-call calibration failed: '+name)


def run():
    """Calibrate selection, freeze owned inputs, then publish complete state-checked profiles or explicit failure."""
    BUILD.mkdir(parents=True, exist_ok=True)
    for name in ('results.json', 'partial.json', 'summary.md', 'generated-source-manifest.json',
                 'native-disassembly.log', 'pinky-1-planned-instructions.callgrind'):
        # Refusals retire prior success before platform/tool/setup validation.
        (BUILD/name).unlink(missing_ok=True)
    report = dict(status='running', profiles=[], controls=[], builds=[],
                  clock_policy='Instrumented wall/CPU clocks are discarded; counters are not timing predictions.')
    try:
        if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
            raise RuntimeError('instruction profiles require the Linux x86-64 CI runner')
        if any(shutil.which(name) is None for name in ('valgrind', 'callgrind_annotate', 'nm', 'objdump')):
            raise RuntimeError('missing Callgrind tools')
        checks = NativeChecks(BUILD)
        version = checks.command(['valgrind', '--version'], 'version')
        if version['exit_code'] or version['output'].strip() != VERSION:
            raise RuntimeError('unexpected Valgrind version')
        report.update(valgrind=VERSION, scope=SCOPE, cases=CASES, platform=platform.platform())
        control = ROOT/'tests/support/pvm_profile_control.c'
        modules = working_paths()
        sources = [ROOT/name for name in modules+list(DRIVER)]
        sources += [control, ROOT/'tools/pvm_instruction_profile.py', ROOT/'Makefile',
                    ROOT/'spec/toolchain.json', ROOT/'spec/pins.json', ROOT/'spec/polkavm-pins.json']
        identities = {path: digest(path) for path in sources}
        calibrate_scope(checks, report)
        prepared = prepare_inputs(checks, BUILD) # The shared preparer admits only its maintained complete matrix.
        identities.update(prepared['identities'])
        report['provenance'] = prepared['provenance']
        driver = {name: (ROOT/name).read_bytes() for name in DRIVER}
        frozen = BUILD/'snapshot'
        frozen_hashes = snapshot(frozen, None, driver)
        identities.update({frozen/name: value for name, value in frozen_hashes.items()})
        compiler, _ = installed()
        row, binary = build(checks, compiler, frozen/'tests/performance/pvm_sieve.nim', 'guest',
            cflags=('-g', '-I'+str(frozen/'tests/performance')))
        report['builds'].append(row)
        report['binary_sha256'] = digest(binary)
        source_root, generated_sources = capture_generated_sources(BUILD, ROOT)
        report['generated_sources'] = generated_sources
        report['generated_source_root'] = source_root.relative_to(BUILD).as_posix()
        (BUILD/'generated-source-manifest.json').write_text(
            json.dumps(generated_sources, indent=2)+'\n')
        symbols = checks.command(['nm', '--defined-only', binary], 'symbols')
        if symbols['exit_code'] or not re.search(r'\bexecute_[0-9]+_\w+', symbols['output']):
            raise RuntimeError('native execution symbol unavailable; no whole-process fallback')
        execution_symbols = sorted(set(re.findall(
            r'^[0-9a-f]+\s+[Tt]\s+(execute_[0-9]+_\w+)$', symbols['output'], re.M)))
        if not execution_symbols:
            raise RuntimeError('exact native execution symbols unavailable for calibrated entry reset')
        refused = checks.command([binary], 'assertions',
            environment=dict(os.environ, RAGNAROK_PVM_SIEVE_ASSERT_PROBE='1'), timeout=30)
        passed = (refused['exit_code'] != 0 and '[Assertion Failure]' in refused['output']
                  and 'pvm sieve native assertion control' in refused['output'])
        refused.pop('output')
        report['controls'].append(dict(name='native-assertions', passed=passed, run=refused))
        if not passed:
            raise RuntimeError('checked profile native assertions were not retained')
        inputs = {(guest, limit): (data, expected) for guest, limit, data, expected in prepared['inputs']}
        for guest, limit, mode in CASES:
            # Existing input/reference preparation and strict native full-state checks remain authoritative.
            data, expected = inputs[guest, limit]
            warmups = 12 if mode == 'memo' else 0
            samples = warmups+1
            environment = dict(os.environ, RAGNAROK_PVM_GUEST=guest, RAGNAROK_PVM_PRICING=mode,
                RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0', RAGNAROK_PVM_SIEVE_INPUT=str(data),
                RAGNAROK_PVM_SIEVE_EXPECTED=str(expected), RAGNAROK_PVM_SIEVE_SAMPLES=str(samples))
            name = guest+'-'+str(limit)+'-'+mode
            result, output = collect(checks, binary, name, SCOPE, environment, 900,
                dump_symbols=execution_symbols if warmups else (), executions=samples)
            if result['exit_code']:
                raise RuntimeError('profile guest failed: '+name)
            engine = dict(dynamic='ragnarok', planned='ragnarok_planned', memo='ragnarok_memo')[mode]
            parse_process_output(result['output'], engine, limit, guest, samples=samples)
            text = output.read_text()
            counts = profile_counts(text)
            if execution_entry_count(text) != 1:
                raise RuntimeError('profile must retain exactly one execution entry: '+name)
            if re.search(r'^fn=execute_[0-9]+_\w+', text, re.M) is None:
                raise RuntimeError('profile lacks selected native execution')
            source_files = execution_source_files(text, generated_sources)
            result.pop('output')
            annotation = checks.command(['callgrind_annotate', '--auto=no', '--inclusive=no',
                '--threshold=95', '--show=Ir', output], name+'-annotation', timeout=30)
            if annotation['exit_code'] or 'PROGRAM TOTALS' not in annotation['output']:
                raise RuntimeError('profile annotation failed: '+name)
            source_annotation = checks.command(['callgrind_annotate', '--auto=no',
                '--inclusive=no', '--threshold=95', '--show=Ir', output, *source_files],
                name+'-source-annotation', cwd=source_root, timeout=30)
            if not source_annotation_passed(source_annotation, source_files):
                raise RuntimeError('selected source annotation failed: '+name)
            report['profiles'].append(dict(guest=guest, limit=limit, mode=mode, counts=counts,
                run=result, profile_sha256=digest(output), profile_file=output.name, state_checked=True,
                warmup_executions=warmups, collected_executions=1,
                execution_entry_count=execution_entry_count(text),
                source_files=source_files, source_annotation_log=source_annotation['log']))
        # A separate trace preserves the ordinary source annotations and adds positions for otherwise unattributed line-zero costs.
        guest, limit, mode = 'pinky', 1, 'planned'
        data, expected = inputs[guest, limit]
        environment = dict(os.environ, RAGNAROK_PVM_GUEST=guest, RAGNAROK_PVM_PRICING=mode,
            RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0', RAGNAROK_PVM_SIEVE_INPUT=str(data),
            RAGNAROK_PVM_SIEVE_EXPECTED=str(expected), RAGNAROK_PVM_SIEVE_SAMPLES='1')
        result, output = collect(checks, binary, 'pinky-1-planned-instructions', SCOPE,
            environment, 900, instructions=True)
        if result['exit_code']:
            raise RuntimeError('native instruction trace failed')
        parse_process_output(result['output'], 'ragnarok_planned', limit, guest, samples=1)
        reference = next(row for row in report['profiles'] if
            (row['guest'], row['limit'], row['mode']) == (guest, limit, mode))
        counts = machine_profile_counts(output.read_text(), reference['counts'])
        disassembly = checks.command(['objdump', '--disassemble', '--line-numbers',
            '--no-show-raw-insn', binary], 'native-disassembly', timeout=30)
        if not disassembly_passed(disassembly):
            raise RuntimeError('native execution disassembly unavailable')
        result.pop('output')
        disassembly.pop('output')
        report['machine_profile'] = dict(guest=guest, limit=limit, mode=mode, counts=counts,
            state_checked=True, run=result, profile_sha256=digest(output),
            disassembly=disassembly, disassembly_sha256=digest(ROOT/disassembly['log']),
            binary_sha256=report['binary_sha256'])
        verify_generated_sources(generated_sources, ROOT, source_root)
        for path, expected in identities.items():
            # Concurrent source or fixture mutation cannot label a different executable as this profile.
            if not path.is_file() or digest(path) != expected:
                raise RuntimeError('profile input changed: '+str(path.relative_to(ROOT)))
        if report['binary_sha256'] != digest(binary) or working_paths() != modules:
            raise RuntimeError('profile binary or source membership changed')
        report.update(status='checks-passed', source_sha256={str(p.relative_to(ROOT)): v for p, v in identities.items()})
        lines = ['Checked PVM execution instruction profiles', '', report['clock_policy'], '',
                 '| Guest | Limit | Pricing | Warmups | Instructions |', '| --- | ---: | --- | ---: | ---: |']
        for item in report['profiles']:
            lines.append(f"| {item['guest']} | {item['limit']} | {item['mode']} | {item['warmup_executions']} | {item['counts']['Ir']} |")
        lines += ['', 'One collected invocation per cell; memo executes twelve checked warmups and retains the thirteenth complete function-return dump. All thirteen states are checked. Preparation and state comparison are outside collection.',
                  'Raw call graphs and self-cost annotations retain helper attribution and inlined compiler symbols.',
                  'Generated C, its checksums and source annotations retain executable line attribution.',
                  'An additional state-checked planned Pinky trace retains native instruction positions and disassembly; its Ir must match the source-level invocation.']
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
        (BUILD/'summary.md').write_text('\n'.join(lines)+'\n')
        print('\n'.join(lines))
    except Exception as error:
        # Failed calibration/profiling preserves diagnostics without a completed aggregate.
        report.update(status='failed', error=str(error))
        (BUILD/'partial.json').write_text(json.dumps(report, indent=2)+'\n')
        raise


if __name__ == '__main__':
    # Importing parsers never provisions tools or launches native profiles.
    run()
