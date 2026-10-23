#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Admit explicitly selected local builds for matched, sequential strict-reopen observations."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import sys
import tempfile
from compare_storage_reopens import compare, read_report
from storage_benchmark import atomic_text, component_hashes, crypto_components, cpu_model
from storage_fresh_reopen import ROOT, CHILD, CASES, parse_prepared, parse_reopened, selected_hashes
from storage_resource_validation import python_identity, validate_counters, validate_checks, digest
from storage_environment import environment, validate_environment
from pvm_reference import command

LABELS = ('baseline', 'candidate')
MAX_CONFIG_BYTES = 65536


def sha256(path):
    """Hash a regular input incrementally without retaining a binary-sized Python allocation."""
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def local_artifact(value):
    """Require an existing, caller-selected regular file below this checkout's ignored build directory."""
    if type(value) is not str or not value or '\x00' in value:
        raise ValueError('Invalid local artifact path')
    path = Path(value)
    if not path.is_absolute():
        path = ROOT/path
    # Reject traversal and symlink aliases before opening; reports never choose executable paths.
    if '..' in path.parts or not path.is_relative_to(ROOT/'build'):
        raise ValueError('Local artifact must be below build')
    cursor = path
    while cursor != ROOT:
        if cursor.is_symlink():
            raise ValueError('Local artifact symlink is forbidden')
        cursor = cursor.parent
    if not path.is_file():
        raise ValueError('Local artifact is not a regular file')
    return path


def read_config(path):
    """Bound and validate the explicit local configuration independently of imported evidence."""
    with path.open('rb') as source:
        raw = source.read(MAX_CONFIG_BYTES+1)
    if len(raw) > MAX_CONFIG_BYTES:
        raise ValueError('Paired configuration exceeds 64 KiB')
    value = json.loads(raw)
    if (type(value) is not dict or set(value) != {'schema_version','baseline','candidate','allow_sources'} or
            type(value['schema_version']) is not int or value['schema_version'] != 1 or
            type(value['allow_sources']) is not list or
            any(type(name) is not str for name in value['allow_sources']) or
            len(set(value['allow_sources'])) != len(value['allow_sources'])):
        raise ValueError('Invalid paired configuration')
    for label in LABELS:
        if type(value[label]) is not dict or set(value[label]) != {'report','binary'}:
            raise ValueError('Invalid paired local build selection')
    return value


def provider_hashes():
    """Observe the providers the fixed native rpath will actually load on this host."""
    suffix = '.dylib' if platform.system() == 'Darwin' else '.so'
    return component_hashes(crypto_components(ROOT/'build/crypto'/('libragnarok_crypto'+suffix)))


def admit(config):
    """Require complete comparable reports, exact local executable/provider hashes and unchanged observers."""
    reports = {}; binaries = {}
    for label in LABELS:
        selection = config[label]
        reports[label] = read_report(local_artifact(selection['report']))
        binaries[label] = local_artifact(selection['binary'])
    # All native work, flags, source inventories and selected namespace bytes are checked by the shared validator.
    compare(reports['baseline'], reports['candidate'], config['allow_sources'])
    providers = provider_hashes()
    for label in LABELS:
        report = reports[label]; binary = binaries[label]
        if not os.access(binary, os.X_OK) or sha256(binary) != report['native_binary_sha256']:
            raise ValueError('Selected local executable differs: '+label)
        with binary.open('rb') as source:
            magic = source.read(4)
        if magic not in (b'\x7fELF', b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'):
            raise ValueError('Selected executable is not a native ELF/Mach-O build')
        if report['inputs']['python_identity'] != python_identity():
            raise ValueError('Paired interpreter differs')
        if report['inputs']['native_components'] != providers:
            raise ValueError('Paired current native providers differ')
        # Current parsers/counters must interpret the same fixture that produced both frozen reports.
        observer_names = [str(CHILD.relative_to(ROOT)), 'tests/performance/storage_fresh_reopen.nim']
        observer_names += [str(p.relative_to(ROOT)) for p in sorted((ROOT/'tools').glob('storage_*.py'))]
        for name in observer_names:
            if sha256(ROOT/name) != report['inputs']['sources'].get(name):
                raise ValueError('Paired current observer differs: '+name)
    return reports, binaries


def host_identity():
    """Record stable host identity without claiming exclusive CPU, cold cache or absent ambient pressure."""
    return dict(system=platform.system(), release=platform.release(), machine=platform.machine(),
                cpu=cpu_model(), page_size=os.sysconf('SC_PAGE_SIZE'))


def driver_hashes():
    """Keep this optional driver outside the historical benchmark inventory and identify it separately."""
    return {name: sha256(ROOT/'tools'/name) for name in
            ('paired_storage_reopens.py', 'compare_storage_reopens.py')}


def execution_plan():
    """Two reversed case and binary orders use both producer directions and exactly sixteen fresh opens."""
    for turn in range(2):
        cases = CASES if turn == 0 else tuple(reversed(CASES))
        order = LABELS if turn == 0 else tuple(reversed(LABELS))
        for engine, count in cases:
            yield turn, engine, count, LABELS[turn], order


def same_environment(left, right):
    """Available disk bytes may vary; geometry, cache policy and inherited limits must stay equal."""
    return {k:v for k,v in left.items() if k != 'available_bytes'} == {
            k:v for k,v in right.items() if k != 'available_bytes'}


def output_folder(path):
    """Create one exclusive private report directory under build, refusing symlink aliases and stale results."""
    path = path if path.is_absolute() else ROOT/path
    if '..' in path.parts or not path.is_relative_to(ROOT/'build'):
        raise ValueError('Paired output must be below build')
    cursor = path
    while cursor != ROOT:
        if cursor.is_symlink():
            raise ValueError('Paired output symlink is forbidden')
        cursor = cursor.parent
    path.mkdir(mode=0o700)
    return path


def collect(config, folder, *, execute_local_builds=False):
    """Execute only explicitly consented local builds with source-owned argv; imported commands remain inert."""
    if execute_local_builds is not True:
        raise ValueError('Paired collection requires --execute-local-builds')
    reports, binaries = admit(config)
    folder = output_folder(folder)
    report = dict(schema_version=1, status='running', reports=reports,
                  allowed_source_changes=config['allow_sources'],
                  binary_paths={name:str(path) for name,path in binaries.items()},
                  binary_sha256={name:reports[name]['native_binary_sha256'] for name in LABELS},
                  driver_sha256=driver_hashes(), host_start=host_identity(),
                  environment_start=environment(folder), output=str(folder), rows=[], checks=[])
    def save():
        """Persist partial/failure receipts atomically, never leaving an old successful summary."""
        atomic_text(folder/'results.json', json.dumps(report, indent=2)+'\n')
    save()
    try:
        for original in reports.values():
            if not same_environment(original['environment'], report['environment_start']):
                raise ValueError('Paired local environment differs from frozen input')
        for turn, engine, count, producer, order in execution_plan():
            # Producer-owned temporary namespaces are always retired, including subprocess/refusal failures.
            prefix = f'pass{turn}-{engine}-{count}'
            with tempfile.TemporaryDirectory(prefix=prefix+'-', dir=folder) as owned:
                prepared = command([str(binaries[producer]),'prepare',engine,str(count),owned],
                                   prefix+'-prepare', folder, timeout=300)
                report['checks'].append(prepared); save()
                if prepared['exit_code'] != 0:
                    raise ValueError('Paired producer failed')
                prepared_raw = Path(prepared['log']).read_text()
                root = parse_prepared(prepared_raw, engine, count)
                selected = selected_hashes(Path(owned)/'store')
                for original in reports.values():
                    expected = next(r for r in original['rows'] if r['case'] == [engine,count])
                    if root != expected['root'] or selected != expected['selected_before']:
                        raise ValueError('Paired producer changed physical work')
                for label in order:
                    counter_path = folder/(prefix+'-'+label+'-resources.json')
                    executed = command([sys.executable,str(CHILD),str(counter_path),str(binaries[label]),
                                        'open',engine,str(count),owned,root],
                                       prefix+'-'+label, folder, timeout=300)
                    report['checks'].append(executed); save()
                    if executed['exit_code'] != 0:
                        raise ValueError('Paired consumer failed')
                    raw = Path(executed['log']).read_text()
                    observed = parse_reopened(raw, engine, count, root)
                    resources = read_report(counter_path); validate_counters(resources)
                    after = selected_hashes(Path(owned)/'store')
                    if after != selected:
                        raise ValueError('Paired consumer changed selected bytes')
                    expected = next(r for r in reports[label]['rows'] if r['case'] == [engine,count])
                    if any(observed[k] != expected['observed'][k] for k in ('stored_nodes','checks')):
                        raise ValueError('Paired consumer changed physical work')
                    report['rows'].append(dict(turn=turn, backend=engine, count=count, binary=label,
                        owned=owned, root=root, prepared_raw=prepared_raw, raw=raw,
                        observed=observed, resources=resources, selected_before=selected, selected_after=after))
                    save()
        report['host_end'] = host_identity(); report['environment_end'] = environment(folder)
        if (report['host_start'] != report['host_end'] or
                not same_environment(report['environment_start'], report['environment_end']) or
                driver_hashes() != report['driver_sha256']):
            raise ValueError('Paired host/environment/driver drift')
        for label in LABELS:
            if sha256(binaries[label]) != report['binary_sha256'][label]:
                raise ValueError('Paired executable drift')
        if provider_hashes() != reports['baseline']['inputs']['native_components']:
            raise ValueError('Paired provider drift')
        report['status'] = 'checks-passed'
        summary = render_pair(report); save()
        atomic_text(folder/'summary.md', summary)
        return report
    except BaseException as error:
        report.update(status='failed', error=str(error)); save()
        raise


def validate_host(value):
    """Host metadata identifies the paired run without claiming exclusive scheduling or cache state."""
    if (type(value) is not dict or set(value) != {'system','release','machine','cpu','page_size'} or
            value['system'] not in ('Darwin','Linux') or
            any(type(value[k]) is not str or not 0 < len(value[k]) <= 4096 or '\x00' in value[k]
                for k in ('system','release','machine','cpu')) or
            type(value['page_size']) is not int or not 512 <= value['page_size'] <= 1<<24 or
            value['page_size'] & (value['page_size']-1)):
        raise ValueError('Invalid paired host identity')


def metadata_path(value):
    """Admit canonical absolute build-local path metadata without opening any imported file."""
    if type(value) is not str or not value or '\x00' in value or len(value) > 4096:
        raise ValueError('Invalid paired path metadata')
    path = Path(value)
    if (not path.is_absolute() or not path.is_relative_to(ROOT/'build') or
            '..' in path.parts or str(path) != value):
        raise ValueError('Invalid paired build path metadata')
    return path


def validate_pair(report):
    """Reparse every native witness and exact execution vector; imported paths never authorize execution or I/O."""
    if (type(report) is not dict or report.get('status') != 'checks-passed' or report.get('error') or
            type(report.get('schema_version')) is not int or report['schema_version'] != 1):
        raise ValueError('Invalid paired report status/schema')
    reports = report.get('reports'); hashes = report.get('binary_sha256'); paths = report.get('binary_paths')
    if any(type(value) is not dict or set(value) != set(LABELS) for value in (reports,hashes,paths)):
        raise ValueError('Invalid paired input coverage')
    allowed = report.get('allowed_source_changes')
    if type(allowed) is not list or any(type(v) is not str for v in allowed) or len(set(allowed)) != len(allowed):
        raise ValueError('Invalid paired source approvals')
    compare(reports['baseline'], reports['candidate'], allowed)
    for label in LABELS:
        metadata_path(paths[label])
        if not digest(hashes[label]) or hashes[label] != reports[label]['native_binary_sha256']:
            raise ValueError('Invalid paired executable identity')
    drivers = report.get('driver_sha256')
    if (type(drivers) is not dict or set(drivers) != {'paired_storage_reopens.py','compare_storage_reopens.py'} or
            any(not digest(v) for v in drivers.values())):
        raise ValueError('Invalid paired driver identity')
    validate_host(report.get('host_start')); validate_host(report.get('host_end'))
    if report['host_start'] != report['host_end']:
        raise ValueError('Paired host drift')
    for name in ('environment_start','environment_end'):
        validate_environment(report.get(name))
        for original in reports.values():
            if not same_environment(report[name], original['environment']):
                raise ValueError('Paired environment drift')
    folder = metadata_path(report.get('output'))
    rows = report.get('rows')
    if type(rows) is not list or len(rows) != 16:
        raise ValueError('Incomplete paired consumer coverage')
    checks = validate_checks(report.get('checks'), 24)
    namespaces = set(); row_index = 0; check_index = 0
    for turn, engine, count, producer, order in execution_plan():
        prefix = f'pass{turn}-{engine}-{count}'
        first = rows[row_index]
        if type(first) is not dict:
            raise ValueError('Invalid paired row')
        owned = metadata_path(first.get('owned'))
        if owned.parent != folder or not owned.name.startswith(prefix+'-') or str(owned) in namespaces:
            raise ValueError('Invalid paired namespace ownership')
        namespaces.add(str(owned))
        expected_prepare = [paths[producer],'prepare',engine,str(count),str(owned)]
        if checks[check_index]['command'] != expected_prepare:
            raise ValueError('Substituted paired producer command')
        check_index += 1
        for label in order:
            row = rows[row_index]; row_index += 1
            if (type(row) is not dict or type(row.get('turn')) is not int or type(row.get('count')) is not int or
                    (row.get('turn'),row.get('backend'),row.get('count'),row.get('binary'),row.get('owned')) !=
                    (turn,engine,count,label,str(owned)) or
                    type(row.get('prepared_raw')) is not str or type(row.get('raw')) is not str):
                raise ValueError('Invalid paired case/order')
            root = parse_prepared(row['prepared_raw'], engine, count)
            original = next(r for r in reports[label]['rows'] if r['case'] == [engine,count])
            observed = parse_reopened(row['raw'], engine, count, root)
            if (root != row.get('root') or root != original['root'] or
                    json.dumps(observed,sort_keys=True) != json.dumps(row.get('observed'),sort_keys=True) or
                    any(observed[k] != original['observed'][k] for k in ('stored_nodes','checks')) or
                    row.get('selected_before') != original['selected_before'] or
                    row.get('selected_after') != original['selected_before']):
                raise ValueError('Substituted paired native work or selected bytes')
            validate_counters(row.get('resources'))
            counters = folder/(prefix+'-'+label+'-resources.json')
            expected_open = [reports[label]['inputs']['python_identity']['executable'],str(CHILD),
                             str(counters),paths[label],'open',engine,str(count),str(owned),root]
            if checks[check_index]['command'] != expected_open:
                raise ValueError('Substituted paired consumer command')
            check_index += 1
    return rows


def render_pair(report):
    """Publish descriptive RSS and retained Nim ranges only after complete read-only validation."""
    rows = validate_pair(report)
    host = report['host_start']
    lines = ['# Matched strict reopen observations', '',
             f'Host: {host["system"]} {host["release"]}, {host["machine"]}, {host["cpu"]}.',
             'Two reversed case/binary orders, both producer directions, identical selected bytes and complete release.',
             'Whole-child high-water RSS differs from retained live Nim allocation. No speed, cold-cache or out-of-core claim.', '',
             '| Backend | Entries | Baseline RSS MiB | Candidate RSS MiB | Baseline live Nim MiB | Candidate live Nim MiB |',
             '| --- | ---: | ---: | ---: | ---: | ---: |']
    for engine, count in CASES:
        values = []
        for metric in ('rss','live'):
            for label in LABELS:
                selected = [r for r in rows if (r['backend'],r['count'],r['binary']) == (engine,count,label)]
                samples = [(r['resources']['peak_rss_bytes'] if metric == 'rss' else
                            r['observed']['opened_bytes']-r['observed']['baseline'])/1048576 for r in selected]
                values.append(f'{min(samples):.1f}–{max(samples):.1f}')
        lines.append(f'| {engine} | {count} | '+ ' | '.join(values)+' |')
    return '\n'.join(lines)+'\n'


def main():
    """Inspection/validation are read-only; native collection requires explicit local-build execution consent."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--execute-local-builds', action='store_true')
    parser.add_argument('--validate', type=Path)
    parser.add_argument('--summary', type=Path)
    args = parser.parse_args()
    if args.validate is not None:
        if args.config is not None or args.output is not None or args.execute_local_builds:
            parser.error('--validate cannot select or execute local builds')
        if args.summary is not None:
            if args.summary.resolve() == args.validate.resolve():
                parser.error('Summary must not replace its source report')
            args.summary.unlink(missing_ok=True)
        summary = render_pair(read_report(args.validate))
        if args.summary is not None:
            args.summary.parent.mkdir(parents=True, exist_ok=True)
            atomic_text(args.summary, summary)
        else:
            print(summary, end='')
        return
    if args.config is None or args.summary is not None:
        parser.error('Select --config or --validate; --summary requires --validate')
    config = read_config(args.config)
    if args.output is not None:
        report = collect(config, args.output, execute_local_builds=args.execute_local_builds)
        print('Paired collection: '+report['status'])
        return
    if args.execute_local_builds:
        parser.error('--execute-local-builds requires --output')
    reports, binaries = admit(config)
    print(json.dumps(dict(status='inputs-admitted',
                          heads={name: reports[name]['inputs']['head'] for name in LABELS},
                          binaries={name: str(binaries[name]) for name in LABELS}), indent=2))


if __name__ == '__main__':
    main()
