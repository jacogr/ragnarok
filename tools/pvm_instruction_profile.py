#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Attribute checked Linux guest execution with calibrated Callgrind; instrumented clocks are never timings.

Make owns setup. The maintained full-state guest driver runs once per selected workload/policy.
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
CASES = (('pinky', 1, 'dynamic'), ('pinky', 1, 'planned'), ('sieve', 100000, 'planned'))
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


def calibration_passed(result, text, selected):
    """A matching selected function collects instructions; a deliberately absent scope collects none."""
    if result['exit_code'] or result['output'].strip() != 'PVM profile calibration passed':
        return False
    try:
        counts = profile_counts(text, allow_empty=not selected)
    except ValueError:
        return False
    return ((counts['Ir'] > 0 and 'fn=pvm_profile_selected' in text
             and 'fn=pvm_profile_outside' not in text) if selected else counts['Ir'] == 0)



def capture_generated_sources(folder, repository):
    """Retain exact generated C at its recorded relative paths for offline source annotation."""
    folder, repository = Path(folder).resolve(), Path(repository).resolve()
    archive = folder/'generated-source'
    if archive.is_symlink():
        # An old archive cannot redirect new generated files outside this verification group.
        raise ValueError('generated source archive is a symlink')
    if archive.exists():
        shutil.rmtree(archive)
    archive.mkdir(parents=True)
    manifest = {}
    for source in sorted(folder.glob('compiler-*/guest-cache/c/**/*.c')):
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


def collect(checks, binary, name, scope, environment, timeout):
    """Collect only the named native execution function; a new private output file cannot reuse stale counters."""
    output = checks.folder/(name+'.callgrind')
    output.unlink(missing_ok=True)
    result = checks.command(['valgrind', '--tool=callgrind', '--collect-atstart=no',
        '--toggle-collect='+scope, '--cache-sim=no', '--branch-sim=yes',
        '--compress-strings=no', '--callgrind-out-file='+str(output),
        '--log-file='+str(checks.folder/(name+'-valgrind.log')), binary], name,
        environment=environment, timeout=timeout)
    if not output.is_file():
        raise RuntimeError('Callgrind did not produce a profile: '+name)
    return result, output


def run():
    """Calibrate selection, freeze owned inputs, then publish complete state-checked profiles or explicit failure."""
    BUILD.mkdir(parents=True, exist_ok=True)
    for name in ('results.json', 'partial.json', 'summary.md', 'generated-source-manifest.json'):
        # Refusals retire prior success before platform/tool/setup validation.
        (BUILD/name).unlink(missing_ok=True)
    report = dict(status='running', profiles=[], controls=[], builds=[],
                  clock_policy='Instrumented wall/CPU clocks are discarded; counters are not timing predictions.')
    try:
        if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
            raise RuntimeError('instruction profiles require the Linux x86-64 CI runner')
        if any(shutil.which(name) is None for name in ('valgrind', 'callgrind_annotate', 'nm')):
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
        compiled = checks.command(['clang', '-O2', '-g', '-o', str(BUILD/'control'), control], 'control-build')
        report['builds'].append({key: value for key, value in compiled.items() if key != 'output'})
        if compiled['exit_code']:
            raise RuntimeError('profile calibration build failed')
        for selected in (True, False):
            # The unmatched scope proves whole-process counts cannot silently substitute for selected execution.
            name = 'control-selected' if selected else 'control-absent'
            result, output = collect(checks, BUILD/'control', name,
                'pvm_profile_selected' if selected else 'pvm_profile_missing', dict(os.environ), 30)
            passed = calibration_passed(result, output.read_text(), selected)
            result.pop('output')
            report['controls'].append(dict(name=name, passed=passed, run=result, profile_sha256=digest(output)))
            if not passed:
                raise RuntimeError('profile scope calibration failed: '+name)
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
            environment = dict(os.environ, RAGNAROK_PVM_GUEST=guest, RAGNAROK_PVM_PRICING=mode,
                RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0', RAGNAROK_PVM_SIEVE_INPUT=str(data),
                RAGNAROK_PVM_SIEVE_EXPECTED=str(expected), RAGNAROK_PVM_SIEVE_SAMPLES='1')
            name = guest+'-'+str(limit)+'-'+mode
            result, output = collect(checks, binary, name, SCOPE, environment, 900)
            if result['exit_code']:
                raise RuntimeError('profile guest failed: '+name)
            parse_process_output(result['output'], 'ragnarok_planned' if mode == 'planned' else 'ragnarok',
                                 limit, guest, samples=1)
            text = output.read_text()
            counts = profile_counts(text)
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
                run=result, profile_sha256=digest(output), state_checked=True,
                source_files=source_files, source_annotation_log=source_annotation['log']))
        verify_generated_sources(generated_sources, ROOT, source_root)
        for path, expected in identities.items():
            # Concurrent source or fixture mutation cannot label a different executable as this profile.
            if not path.is_file() or digest(path) != expected:
                raise RuntimeError('profile input changed: '+str(path.relative_to(ROOT)))
        if report['binary_sha256'] != digest(binary) or working_paths() != modules:
            raise RuntimeError('profile binary or source membership changed')
        report.update(status='checks-passed', source_sha256={str(p.relative_to(ROOT)): v for p, v in identities.items()})
        lines = ['Checked PVM execution instruction profiles', '', report['clock_policy'], '',
                 '| Guest | Limit | Pricing | Instructions |', '| --- | ---: | --- | ---: |']
        for item in report['profiles']:
            lines.append(f"| {item['guest']} | {item['limit']} | {item['mode']} | {item['counts']['Ir']} |")
        lines += ['', 'One full-state-checked invocation per cell; fixture preparation and full-state comparison are outside collection.',
                  'Raw call graphs and self-cost annotations retain helper attribution and inlined compiler symbols.',
                  'Generated C, its checksums and source annotations retain executable line attribution.']
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
