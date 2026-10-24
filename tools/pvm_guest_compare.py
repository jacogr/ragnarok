#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare a resolved PVM revision and working sources using one checked driver and paired guests.

Make owns provisioning. Only library sources vary; fixtures, driver, compiler, flags and pricing
policies stay fixed. Successful reports require complete state checks and unchanged byte identities.
"""
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import statistics
import subprocess

from native_checks import NativeChecks, ROOT
from pvm_benchmark import cpu_model
from pvm_guest_inputs import CASES, digest, prepare_inputs, validate_cases
from pvm_opcode_census import build
from pvm_sieve_report import (parse_process_output, validate_samples, validate_preparation,
                              validate_memo_preparation)
from setup_nimony import installed


BUILD = ROOT/'build/tests/pvm-guest-compare'
MODES = {'dynamic': 'ragnarok', 'planned': 'ragnarok_planned', 'memo': 'ragnarok_memo'}
DRIVER = ('tests/performance/pvm_sieve.nim', 'tests/performance/pvm_sieve_clock.h')


def git(*arguments):
    """Pass revision/path arguments directly to Git, without shell expansion or network access."""
    return subprocess.check_output(['git', '-C', str(ROOT), *arguments])


def revision(value):
    """Resolve a caller-supplied ref once; only the resulting immutable commit names source reads."""
    if type(value) is not str or not value:
        raise ValueError('PVM_COMPARE_BASE must name a local commit or ref')
    resolved = git('rev-parse', '--verify', '--end-of-options', value+'^{commit}').decode().strip()
    if len(resolved) not in (40, 64) or any(c not in '0123456789abcdef' for c in resolved):
        raise ValueError('invalid resolved PVM comparison commit')
    return resolved


def source_path(value):
    """Admit only owned PVM modules and the exact shared natural codec; never traverse a snapshot."""
    path = PurePosixPath(value)
    if (path.is_absolute() or '..' in path.parts or path.as_posix() != value
            or not value.endswith('.nim') or not (value.startswith('src/pvm/')
            or value == 'src/codec/natural.nim')):
        raise ValueError('unsupported comparison source path')
    return value


def working_paths():
    """Freeze the current module membership, including new owned modules but excluding foreign symlinks."""
    paths = sorted((ROOT/'src/pvm').rglob('*.nim'))+[ROOT/'src/codec/natural.nim']
    for path in paths:
        # A borrowed source path cannot silently redirect comparison provenance outside the checkout.
        if path.is_symlink() or not path.resolve().is_relative_to(ROOT.resolve()):
            raise ValueError('foreign comparison source')
    return [source_path(path.relative_to(ROOT).as_posix()) for path in paths]


def snapshot(folder, commit, driver):
    """Copy one exact source endpoint; remove prior owned snapshots so deleted modules cannot survive."""
    if set(driver) != set(DRIVER) or any(type(data) is not bytes for data in driver.values()):
        raise ValueError('unsupported comparison driver snapshot')
    if folder.is_symlink() or not folder.resolve().is_relative_to((ROOT/'build').resolve()):
        raise ValueError('comparison snapshots must remain in the owned build directory')
    if folder.exists():
        shutil.rmtree(folder) # This private source-only directory contains no compiler cache or user checkout.
    folder.mkdir(parents=True)
    if commit is None:
        paths = working_paths()
        sources = {path: (ROOT/path).read_bytes() for path in paths}
    else:
        entries = git('ls-tree', '-r', '-z', commit, '--', 'src/pvm',
                      'src/codec/natural.nim').decode().split('\0')
        paths = []
        for entry in entries:
            if not entry:
                continue # Git's NUL terminator is not a source entry.
            header, name = entry.split('\t', 1)
            if name.endswith('.nim'):
                if header.split()[:2] not in (['100644', 'blob'], ['100755', 'blob']):
                    raise ValueError('foreign revision comparison source')
                paths.append(source_path(name))
        sources = {path: git('show', commit+':'+path) for path in paths}
    if not paths or 'src/codec/natural.nim' not in paths:
        raise ValueError('incomplete comparison library source tree')
    sources.update(driver)
    hashes = {}
    for name, data in sources.items():
        # Driver bytes are frozen once and reused on both sides; no historic harness or build script is executed.
        target = folder/name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        hashes[name] = digest(target)
    return hashes


def unchanged(identities):
    """Invalidate the whole comparison if a source, input, dependency or binary changes during the run."""
    for path, expected in identities.items():
        if not path.is_file() or digest(path) != expected:
            raise ValueError('paired guest input changed during run: '+str(path))


def summarize(report):
    """Validate complete opposite-order coverage and show all CPU cells, including regressions and noise."""
    if (not isinstance(report, dict) or report.get('status') != 'checks-passed'
            or type(report.get('cases')) is not list or type(report.get('runs')) is not list):
        raise ValueError('paired guest comparison has not completed')
    cases = tuple((case['guest'], case['limit']) for case in report['cases'])
    validate_cases(cases)
    ordered = [(variant, guest, limit, mode, repeat) for repeat, order in enumerate(
        (('baseline', 'candidate'), ('candidate', 'baseline')))
        for guest, limit in cases for mode in MODES for variant in order]
    wanted = set(ordered)
    seen = set()
    for row in report['runs']:
        # Typed identities and strict samples prevent duplicates or incomplete successes from becoming a summary.
        identity = (row['variant'], row['guest'], row['limit'], row['mode'], row['pass_index'])
        if (type(row['limit']) is not int or type(row['pass_index']) is not int
                or identity not in wanted or identity in seen or row['parsed']['guest'] != row['guest']
                or identity != ordered[len(seen)]):
            raise ValueError('incomplete or duplicate paired guest coverage')
        validate_samples(row['parsed']['samples'])
        preparation = row['parsed']['preparation']
        if row['mode'] == 'planned':
            validate_preparation(preparation)
        elif row['mode'] == 'memo':
            validate_memo_preparation(preparation)
        elif preparation is not None:
            raise ValueError('unplanned paired guest supplied pricing metadata')
        seen.add(identity)
    if report['status'] != 'checks-passed' or seen != wanted:
        raise ValueError('paired guest comparison has not completed')
    lines = ['Paired checked PVM revision comparison (CPU medians; all raw samples retained).', '',
             '| Guest | Limit | Pricing | Baseline ms | Candidate ms | Change |',
             '| --- | ---: | --- | ---: | ---: | ---: |']
    for guest, limit in cases:
        for mode in MODES:
            medians = []
            for variant in ('baseline', 'candidate'):
                samples = [sample['cpu_ns'] for row in report['runs'] if
                    (row['variant'], row['guest'], row['limit'], row['mode']) ==
                    (variant, guest, limit, mode) for sample in row['parsed']['samples'][3:]]
                medians.append(statistics.median(samples)/1e6)
            change = 100*(medians[1]/medians[0]-1)
            lines.append(f'| {guest} | {limit} | {mode} | {medians[0]:.3f} | {medians[1]:.3f} | {change:+.1f}% |')
    if report.get('identical_sources', False):
        lines.append('Identical source endpoints: timing differences are control variation, not a code improvement.')
    lines.extend(['', 'Three warmups and ten measured samples per process; two reversed orders.',
        'Differences below a few percent are unproven; inspect raw spread and repeat suspicious cells.',
        'Preparation and first-cold samples remain in results.json. No universal or Linux speed claim.'])
    return '\n'.join(lines)+'\n'


def run(base_ref, scope='all', folder=None):
    """Build both frozen libraries and publish only after all paired full-state checks and identity guards pass."""
    folder = Path(folder) if folder is not None else BUILD
    if not folder.resolve().is_relative_to((ROOT/'build').resolve()):
        raise ValueError('paired guest output must remain in the owned build directory')
    folder.mkdir(parents=True, exist_ok=True)
    for name in ('results.json', 'partial.json', 'summary.md'):
        (folder/name).unlink(missing_ok=True) # A failed rerun never leaves an earlier successful downloadable summary.
    report = dict(status='running', runs=[], builds=[], controls=[], cases=[], endpoints={})
    try:
        baseline = revision(base_ref)
        if type(scope) is not str or scope not in ('all', 'controls'):
            raise ValueError('PVM_COMPARE_SCOPE must be all or controls')
        cases = CASES[:-1] if scope == 'controls' else CASES
        report.update(baseline_commit=baseline, candidate_head_context=revision('HEAD'),
                      candidate_is_working_tree=True, cpu=cpu_model(), platform=platform.platform())
        compiler, _ = installed()
        members = working_paths()
        for path in DRIVER:
            if (ROOT/path).is_symlink() or not (ROOT/path).resolve().is_relative_to(ROOT.resolve()):
                raise ValueError('foreign comparison driver')
        driver = {path: (ROOT/path).read_bytes() for path in DRIVER}
        identities, binaries = {}, {}
        for variant, commit in (('baseline', baseline), ('candidate', None)):
            endpoint = folder/'snapshots'/variant
            hashes = snapshot(endpoint, commit, driver)
            report['endpoints'][variant] = hashes
            identities.update({endpoint/path: value for path, value in hashes.items()})
            if commit is None:
                identities.update({ROOT/path: value for path, value in hashes.items()})
        for name in ('pvm_guest_compare.py', 'pvm_guest_inputs.py', 'pvm_sieve_report.py',
                     'pvm_sieve_benchmark.py', 'pvm_benchmark.py', 'pvm_benchmark_report.py',
                     'native_checks.py', 'native_dependencies.py', 'native_fixture_contracts.py',
                     'pvm_opcode_census.py', 'setup_nimony.py'):
            identities[ROOT/'tools'/name] = digest(ROOT/'tools'/name)
        prepared = prepare_inputs(NativeChecks(folder, reuse_builds=True), folder/'inputs', cases)
        identities.update(prepared['identities'])
        identities[compiler] = digest(compiler)
        report.update(provenance=prepared['provenance'], preparations=prepared['preparations'],
                      cases=[dict(guest=guest, limit=limit) for guest, limit in cases])
        report['builds'].extend(prepared['builds'])
        checks = NativeChecks(folder, reuse_builds=True)
        for variant in ('baseline', 'candidate'):
            endpoint = folder/'snapshots'/variant
            row, binary = build(checks, compiler, endpoint/DRIVER[0], 'native-'+variant,
                              cflags=('-I'+str(endpoint/'tests/performance'),))
            report['builds'].append(row)
            binaries[variant] = binary
            identities[binary] = digest(binary)
            control = checks.command([binary], variant+'-assertion-control', environment=dict(
                os.environ, RAGNAROK_PVM_GUEST='sieve', RAGNAROK_PVM_SIEVE_ASSERT_PROBE='1'))
            output = control.pop('output')
            if (control['exit_code'] == 0 or '[Assertion Failure]' not in output
                    or 'pvm sieve native assertion control' not in output):
                raise RuntimeError('paired guest assertion control failed: '+variant)
            report['controls'].append(dict(variant=variant, run=control, passed=True))
        for repeat, order in enumerate((('baseline', 'candidate'), ('candidate', 'baseline'))):
            for guest, limit, data, expected in prepared['inputs']:
                for mode, engine in MODES.items():
                    for variant in order:
                        # Fresh processes retain full cold/warm observations and validate every complete CPU/gas/page image.
                        environment = dict(os.environ, RAGNAROK_PVM_GUEST=guest,
                            RAGNAROK_PVM_PRICING=mode, RAGNAROK_PVM_SIEVE_INPUT=str(data),
                            RAGNAROK_PVM_SIEVE_EXPECTED=str(expected), RAGNAROK_PVM_SIEVE_SAMPLES='13',
                            RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0')
                        result = checks.command([binaries[variant]],
                            f'{repeat}-{guest}-{limit}-{mode}-{variant}', environment=environment, timeout=180)
                        output = result.pop('output')
                        if result['exit_code']:
                            raise RuntimeError('paired guest execution failed: '+result['log'])
                        parsed = parse_process_output(output, engine, limit, guest)
                        report['runs'].append(dict(variant=variant, guest=guest, limit=limit,
                            mode=mode, pass_index=repeat, parsed=parsed, run=result))
                        (folder/'partial.json').write_text(json.dumps(report, indent=2)+'\n')
            print('Completed paired guest order', repeat+1, flush=True)
        unchanged(identities)
        if working_paths() != members:
            raise ValueError('paired guest source membership changed during run')
        report.update(status='checks-passed', validated_invocations=len(report['runs'])*13,
                      identical_sources=report['endpoints']['baseline'] == report['endpoints']['candidate'],
                      identity_sha256={str(path.relative_to(ROOT)): value for path, value in identities.items()},
                      binary_sha256={name: digest(path) for name, path in binaries.items()})
        summary = summarize(report)
        (folder/'results.json').write_text(json.dumps(report, indent=2)+'\n')
        (folder/'summary.md').write_text(summary)
        print(summary)
        return report
    except Exception as error:
        # Partial diagnostics remain explicitly failed; no completed aggregate or summary survives.
        report.update(status='failed', error=str(error))
        (folder/'partial.json').write_text(json.dumps(report, indent=2)+'\n')
        (folder/'results.json').unlink(missing_ok=True)
        (folder/'summary.md').unlink(missing_ok=True)
        raise


if __name__ == '__main__':
    scope = os.environ.get('RAGNAROK_PVM_COMPARE_SCOPE', '') or 'all'
    run(os.environ.get('RAGNAROK_PVM_COMPARE_BASE', ''), scope=scope)
