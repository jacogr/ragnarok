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
from storage_resource_validation import python_identity, validate_counters
from storage_environment import environment
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
        report['status'] = 'checks-passed'; save()
        return report
    except BaseException as error:
        report.update(status='failed', error=str(error)); save()
        raise


def main():
    """Input inspection grants no authority to execute any imported report command."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--execute-local-builds', action='store_true')
    args = parser.parse_args()
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
