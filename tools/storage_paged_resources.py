#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build checked paged probes separately from serial fresh processes under an existing no-swap Linux cgroup."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import time
import os
import select
import uuid
from pathlib import PurePosixPath

from native_checks import NativeChecks
from native_preparation import prepare_libraries
from setup_nimony import ROOT, installed
from storage_benchmark import atomic_text, source_hashes
from storage_resource_panel import panel_identity
from storage_resource_validation import validate_counters
from storage_limit_cgroup import resolve, parse_files, FILES

BUILD = ROOT/'build/tests/storage-paged-resources'
SOURCE = ROOT/'tests/performance/storage_paged_resources.nim'
HEADER = SOURCE.with_suffix('.h')
CHILD = ROOT/'tools/storage_resource_child.py'
CASES = tuple((count, cache) for count in (16384, 327680) for cache in (0, 1))
ROOT_HEX = '95d1185009f2c76ee7ba51f996a2d66613fc3b9f239b7a18d2f46fd71145d343'
MEMORY = 64*1024*1024


def geometry(count):
    """Independent integer page/tree arithmetic supplies expected populated extents without a resident artifact."""
    pages = 1+(count*64+4095)//4096+(count*169+4097+4095)//4096
    leaves = 1 << (pages-1).bit_length()
    return pages, pages*4096+(2*leaves-1)*32


def parse(raw, mode, count, cache):
    """Only an exact independently rooted native receipt with released heap/handles and complete query checks succeeds."""
    fields = raw.strip().split('\t')
    if (len(fields) != 19 or fields[:4] != [mode, str(count), str(cache), ROOT_HEX] or
            any(re.fullmatch(r'0|[1-9][0-9]{0,18}', value) is None for value in fields[4:])):
        raise ValueError('Invalid paged native receipt identity')
    names = ('file_bytes', 'pages', 'baseline', 'opened', 'released', 'fd_baseline', 'fd_opened',
             'fd_released', 'read_calls', 'write_calls', 'hash_calls', 'queries', 'peak_rss_bytes', 'minor_faults', 'major_faults')
    row = dict(zip(names, map(int, fields[4:])))
    pages, size = geometry(count)
    if (any(value >= 1 << 63 for value in row.values()) or
            (row['pages'], row['file_bytes']) != (pages, size) or
            not 0 < row['opened']-row['baseline'] < 65536 or row['released'] != row['baseline'] or
            row['fd_baseline'] < 3 or row['fd_released'] != row['fd_baseline'] or
            row['fd_opened']-row['fd_baseline'] != (4 if mode == 'prepare' else 2) or
            row['read_calls'] <= count or row['hash_calls'] <= count or
            row['queries'] != (0 if mode == 'prepare' else 1028) or
            (row['write_calls'] < count*2 if mode == 'prepare' else row['write_calls'] != 0)):
        raise ValueError('Invalid paged native resource witnesses')
    validate_counters({name: row[name] for name in ('peak_rss_bytes', 'minor_faults', 'major_faults')})
    return row


def inputs(compiler, library, binary):
    """Freeze compiler, complete production storage/crypto closure, observer providers and measurement helpers."""
    value = panel_identity(compiler, library, SOURCE)
    value['sources'].update(source_hashes([HEADER, Path(__file__), ROOT/'Dockerfile',
        ROOT/'tests/native/storage_io_observer.c', ROOT/'tests/native/crypto_observer.c',
        *sorted((ROOT/'native/storage_io').glob('*.h'))]))
    observed = BUILD/('libcrypto_observed.dylib' if platform.system() == 'Darwin' else 'libcrypto_observed.so')
    value['observers'] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in (observed, BUILD/'storage-io-observer.o')}
    value['binary_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
    return value


def build():
    """Make provisions tools first; compiler/provider work runs outside the measured resource cgroup."""
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD/'build.json').unlink(missing_ok=True)
    libraries, _, providers = prepare_libraries(BUILD, required={'crypto', 'observer', 'storage_io'})
    compiler, _ = installed()
    flags = ['-I'+str(ROOT/'native/storage_io'), '-I'+str(HEADER.parent),
             '-include'+str(ROOT/'native/storage_io/redirect.h')]
    flags += ['-DRAGNAROK_STORAGE_IO_'+name for name in ('READ', 'WRITE', 'CLOSE', 'FSYNC', 'FLOCK')]
    receipt, binary = NativeChecks(BUILD).build(compiler, SOURCE, 'paged-native',
        crypto_library=libraries['observer'], native_libraries=(libraries['storage_io'],), cflags=flags)
    receipt.pop('output', None)
    if receipt['exit_code'] != 0:
        raise RuntimeError('Paged checked build failed: '+receipt['log'])
    record = dict(build=receipt, providers=providers, inputs=inputs(compiler, libraries['crypto'], binary),
                  compiler=str(compiler), library=str(libraries['crypto']), binary=str(binary))
    atomic_text(BUILD/'build.json', json.dumps(record, indent=2)+'\n')
    print('PASS paged checked probe build: '+str(BUILD/'build.json'), flush=True)


def kernel():
    """Read actual namespace membership and kernel controls; unsupported hosts refuse strict qualification."""
    membership = Path('/proc/self/cgroup').read_text()
    mounts = Path('/proc/self/mountinfo').read_text()
    group = Path(resolve(membership, mounts))
    raw = {name: (group/name).read_text() for name in FILES}
    optional = {name: (group/name).read_text() for name in ('memory.peak', 'memory.swap.peak')
                if (group/name).is_file()}
    return dict(membership=membership, mountinfo=mounts, group=str(group), raw=raw, optional=optional)


def controls(receipt, memory):
    """Exact private no-swap limits are mandatory; host RAM or command-line Docker flags alone prove nothing."""
    if resolve(receipt['membership'], receipt['mountinfo']) != receipt['group']:
        raise ValueError('Changed paged cgroup identity')
    values = parse_files(receipt['raw'])
    if (values['memory.max'] != memory or values['memory.swap.max'] != 0 or
            values['memory.swap.current'] != 0 or values['memory.events']['oom'] != 0 or
            values['memory.events']['oom_kill'] != 0):
        raise ValueError('Missing no-swap memory bound or an observed OOM event')
    return values


def selected(path):
    """Hash only the closed synthetic selected namespace, preserving all bytes across strict fresh-reader admission."""
    names = {'LOCK', 'CURRENT', 'paged-0000000000000001.bin'}
    if {entry.name for entry in path.iterdir()} != names:
        raise ValueError('Unexpected paged selected namespace')
    if any((path/name).is_symlink() or not (path/name).is_file() for name in names):
        raise ValueError('Nonregular paged selected namespace')
    result = {}
    for name in sorted(names):
        # Stream hashes never materialize the larger-than-RAM artifact in the observer.
        digest = hashlib.sha256()
        with (path/name).open('rb') as stream:
            for chunk in iter(lambda: stream.read(65536), b''): digest.update(chunk)
        result[name] = digest.hexdigest()
    return result


def run_local(cases):
    """Optional unpressured local observations share the native plan without claiming Linux no-swap qualification."""
    frozen = verify_frozen()
    binary = BUILD/'paged-native'
    target = BUILD/'local-results.json'
    report = dict(status='running', local_only=True, build=frozen, runs=[], host=platform.platform())
    def save():
        """Retain local failures without a stale successful resource verdict."""
        atomic_text(target, json.dumps(report, indent=2)+'\n')
    save()
    try:
        for count, cache in cases:
            with tempfile.TemporaryDirectory(prefix='paged-', dir=BUILD) as owned:
                path = Path(owned)/'store'
                row = dict(count=count, cache=cache, phases=[])
                report['runs'].append(row)
                before = None
                for mode in ('prepare', 'open'):
                    # Fresh local children remain observations only; the Docker path owns enforced Linux evidence.
                    resource = Path(owned)/(mode+'-resources.json')
                    name = f'local-{count}-{cache}-{mode}'
                    arguments = [sys.executable, str(CHILD), str(resource), str(binary), mode,
                                 str(path), str(count), str(cache)]
                    receipt = NativeChecks(BUILD).command(arguments, name, timeout=1800)
                    receipt.pop('output', None)
                    phase = dict(mode=mode, command=receipt)
                    row['phases'].append(phase)
                    if receipt['exit_code'] != 0: raise RuntimeError('Local native paged '+mode+' failed')
                    phase['raw'] = (ROOT/receipt['log']).read_text()
                    phase['native'] = parse(phase['raw'], mode, count, cache)
                    phase['resources'] = validate_counters(json.loads(resource.read_text()))
                    after = selected(path)
                    if mode == 'prepare': before = after
                    elif after != before: raise ValueError('Strict local reader changed selected bytes')
                    phase['selected'] = after
                    save()
        if verify_frozen() != frozen: raise ValueError('Local paged inputs changed')
        report['status'] = 'checks-passed'
        save()
        print('PASS local paged resource observations: '+str(target), flush=True)
    except Exception as error:
        report.update(status='failed', error=type(error).__name__+': '+str(error))
        save()
        raise


def verify_frozen():
    """Verify all frozen inputs outside pressure; no compiler/version or provenance subprocess runs in the limited scope."""
    frozen = json.loads((BUILD/'build.json').read_text())
    compiler, _ = installed()
    library = ROOT/'build/crypto'/('libragnarok_crypto.dylib' if platform.system() == 'Darwin' else 'libragnarok_crypto.so')
    binary = BUILD/'paged-native'
    if [frozen['compiler'], frozen['library'], frozen['binary']] != list(map(str, (compiler, library, binary))):
        raise ValueError('Foreign paged build paths')
    if inputs(compiler, library, binary) != frozen['inputs']:
        raise ValueError('Paged build inputs changed')
    return frozen


def run_docker(image, cases):
    """The observer stays outside pressure; one persistent private cgroup retains page-cache charges across fresh native execs."""
    folder = BUILD/('docker-'+uuid.uuid4().hex)
    folder.mkdir(parents=True)
    report = dict(status='running', commands=[], runs=[], observer_host=platform.platform(),
                  cache_policy='unchanged filesystem cache; constant-size producer; fresh native execs in one persistent64MiB cgroup')
    container = 'ragnarok-paged-'+uuid.uuid4().hex
    created = False
    def save():
        """Publish incremental/failure evidence without ever leaving a stale successful report."""
        atomic_text(folder/'results.json', json.dumps(report, indent=2)+'\n')
    def execute(args, name, timeout=60, required=True):
        """Record exact owned commands and deadlines; a failure never inherits a later command's success."""
        started = time.monotonic()
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        (folder/(name+'.log')).write_text(result.stdout+result.stderr)
        report['commands'].append(dict(name=name, command=args, exit_code=result.returncode,
                                      elapsed_seconds=round(time.monotonic()-started, 6), log=name+'.log'))
        save()
        if required and result.returncode != 0:
            raise RuntimeError('Paged Docker command failed: '+name)
        return result
    def context():
        """Actual exec processes share the same immutable private Docker cgroup as the native writer/readers."""
        def read(path):
            return execute(['docker', 'exec', container, 'cat', path], 'kernel-'+str(len(report['commands']))).stdout
        membership, mounts = read('/proc/self/cgroup'), read('/proc/self/mountinfo')
        group = resolve(membership, mounts)
        raw = {name: read(group+'/'+name) for name in FILES}
        receipt = dict(membership=membership, mountinfo=mounts, group=group, raw=raw)
        controls(receipt, MEMORY)
        return receipt
    def hashes(path):
        """Stream only fixed selected names through a tiny cat process; no Python or dataset-sized observer lives inside pressure."""
        value = {}
        for name in ('CURRENT', 'LOCK', 'paged-0000000000000001.bin'):
            arguments = ['docker', 'exec', container, 'cat', path+'/'+name]
            digest = hashlib.sha256()
            with subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as child:
                # Pipe readiness and an exact owned-process deadline bound even a stalled local Docker connection.
                started = time.monotonic()
                try:
                    while True:
                        remaining = 180-(time.monotonic()-started)
                        if remaining <= 0 or not select.select([child.stdout], [], [], remaining)[0]:
                            raise TimeoutError('Selected hash transfer timeout')
                        chunk = os.read(child.stdout.fileno(), 65536)
                        if not chunk: break
                        digest.update(chunk)
                    code = child.wait(timeout=max(1, 180-(time.monotonic()-started)))
                    error = child.stderr.read(4096)
                    if code != 0 or error: raise RuntimeError('Selected hash transfer failed')
                except Exception:
                    # Retire only this owned transfer before propagating failure to container cleanup.
                    child.kill()
                    child.wait(timeout=10)
                    raise
            report['commands'].append(dict(name='selected-'+str(len(report['commands'])), command=arguments,
                exit_code=code, elapsed_seconds=round(time.monotonic()-started, 6), sha256=digest.hexdigest()))
            value[name] = digest.hexdigest()
        return value
    save()
    try:
        # Resolve a mutable user tag once; every subsequent command binds the content-addressed image.
        image_id = execute(['docker', 'image', 'inspect', image, '--format', '{{.Id}}'], 'image').stdout.strip()
        if re.fullmatch('sha256:[0-9a-f]{64}', image_id) is None: raise ValueError('Invalid Docker image identity')
        report['image'] = image_id
        report['target'] = 'linux/amd64'
        report['engine'] = execute(['docker', 'info', '--format', '{{.OSType}}/{{.Architecture}} cgroup={{.CgroupVersion}}'], 'engine').stdout.strip()
        frozen = json.loads(execute(['docker', 'run', '--rm', '--platform', 'linux/amd64', '--network', 'none',
            image_id, 'python3', 'tools/storage_paged_resources.py', '--verify-only'], 'frozen', timeout=180).stdout)
        report['build'] = frozen
        for name, digest in frozen['inputs']['sources'].items():
            # Image source paths are data; only canonical in-repository files can be compared on this host.
            relative = PurePosixPath(name)
            if relative.is_absolute() or '..' in relative.parts or str(relative) != name:
                raise ValueError('Invalid frozen source path')
            if hashlib.sha256((ROOT/name).read_bytes()).hexdigest() != digest:
                raise ValueError('Host/image source closure differs: '+name)
        execute(['docker', 'create', '--platform', 'linux/amd64', '--network', 'none', '--memory', '64m',
                 '--memory-swap', '64m', '--name', container, image_id, 'sleep', 'infinity'], 'create')
        created = True
        execute(['docker', 'start', container], 'start')
        report['kernel_before'] = context()
        for count, cache in cases:
            path = '/src/build/tests/storage-paged-resources/owned-'+uuid.uuid4().hex
            row = dict(count=count, cache=cache, phases=[])
            report['runs'].append(row)
            before = None
            for mode in ('prepare', 'open'):
                # Exactly one native storage executable runs inside pressure; fixture producer exits before the fresh consumer.
                name = f'{count}-{cache}-{mode}'
                arguments = ['docker', 'exec', container, '/src/build/tests/storage-paged-resources/paged-native',
                             mode, path, str(count), str(cache)]
                receipt = execute(arguments, name, timeout=1800, required=False)
                phase = dict(mode=mode, raw=receipt.stdout, exit_code=receipt.returncode)
                row['phases'].append(phase)
                if receipt.returncode != 0: raise RuntimeError('Native paged '+mode+' failed: '+name)
                phase['native'] = parse(receipt.stdout, mode, count, cache)
                phase['kernel'] = context()
                if phase['native']['peak_rss_bytes'] >= MEMORY:
                    raise ValueError('Native peak RSS exceeded the fixed allowance')
                phase['selected'] = hashes(path)
                if mode == 'prepare': before = phase['selected']
                elif phase['selected'] != before: raise ValueError('Strict reader changed selected files')
                save()
            if count == 327680 and geometry(count)[1] <= MEMORY:
                raise ValueError('Populated selected dataset is not larger than the no-swap allowance')
        report['container'] = json.loads(execute(['docker', 'inspect', container, '--format', '{{json .}}'], 'inspect').stdout)
        if report['container']['State']['OOMKilled']: raise ValueError('Container OOM event')
        # Reverify the same immutable image and the full local source closure after all native runs.
        final = json.loads(execute(['docker', 'run', '--rm', '--platform', 'linux/amd64', '--network', 'none',
            image_id, 'python3', 'tools/storage_paged_resources.py', '--verify-only'], 'frozen-final', timeout=180).stdout)
        if final != frozen: raise ValueError('Frozen image inputs changed')
        for name, digest in frozen['inputs']['sources'].items():
            if hashlib.sha256((ROOT/name).read_bytes()).hexdigest() != digest:
                raise ValueError('Host source changed during qualification')
        report['status'] = 'checks-passed'
        save()
        print('PASS Linux paged resource panel: '+str(folder/'results.json'), flush=True)
    except Exception as error:
        report.update(status='failed', error=type(error).__name__+': '+str(error))
        if created:
            # A killed observer/native process has a distinct kernel/container outcome, never a successful resource row.
            state = execute(['docker', 'inspect', container, '--format', '{{json .State}}'], 'failure-state', required=False)
            report['container_failure'] = state.stdout
            try: report['kernel_failure'] = context()
            except Exception as missing: report['kernel_error'] = str(missing)
        save()
        raise
    finally:
        if created:
            # Retire only this randomly named test-owned cgroup after all available failure evidence is preserved.
            execute(['docker', 'rm', '--force', container], 'retire', required=False)


def main():
    """Build and run are deliberately distinct; optional local mode cannot establish Linux or larger-than-RAM qualification."""
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--build-only', action='store_true')
    mode.add_argument('--run-only', action='store_true')
    mode.add_argument('--verify-only', action='store_true')
    mode.add_argument('--docker', metavar='IMAGE')
    parser.add_argument('--case', choices=['all', *[f'{n}-{c}' for n, c in CASES]], default='all')
    parser.add_argument('--local', action='store_true')
    args = parser.parse_args()
    if args.build_only:
        build()
    elif args.verify_only:
        print(json.dumps(verify_frozen(), sort_keys=True))
    else:
        cases = CASES if args.case == 'all' else (tuple(map(int, args.case.split('-'))),)
        if args.docker: run_docker(args.docker, cases)
        elif args.local: run_local(cases)
        else: parser.error('Use --docker IMAGE for Linux qualification or --run-only --local for local observations')


if __name__ == '__main__':
    main()
