#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Qualify populated full graphs with fresh native execs in one persistent64MiB no-swap cgroup.

Fixture maps/reference artifacts and the Python observer remain outside pressure. Only bounded
source-file producers and native full writers/readers execute inside the constrained cgroup.
"""
import argparse
import hashlib
import json
import platform
import os
import select
import re
import subprocess
import time
import uuid
from pathlib import Path, PurePosixPath

from native_checks import NativeChecks
from native_preparation import prepare_libraries
from setup_nimony import ROOT, installed
from storage_benchmark import atomic_text, source_hashes
from storage_resource_panel import panel_identity
from storage_resource_validation import validate_counters
from storage_paged_resources import controls, MEMORY
from storage_limit_cgroup import resolve, FILES

BUILD = ROOT/'build/tests/storage-full-paged-resources'
SOURCE = ROOT/'tests/performance/storage_full_paged_resources.nim'
HEADER = ROOT/'tests/performance/storage_paged_resources.h'
VALUE_BYTES = 1048576
COUNTS = (2, 8, 72, 2048)
CASES = tuple((count, cache) for count in COUNTS for cache in (0, 1))


def geometry(records, payload):
    """Independent fixed-page/tree arithmetic binds all native dataset extent claims."""
    pages = 1+(records*64+4095)//4096+(payload+4095)//4096
    leaves = 1 << (pages-1).bit_length()
    return pages, pages*4096+(2*leaves-1)*32


def fixture(raw, count):
    """Validate independent complete-map/source metadata before passing scalar authority into pressure."""
    fields = raw.strip().split('\t')
    if (count not in COUNTS or len(fields) != 6 or fields[0] != str(count) or re.fullmatch('[0-9a-f]{64}', fields[1]) is None or
            any(re.fullmatch(r'0|[1-9][0-9]{0,9}', value) is None for value in fields[2:])):
        raise ValueError('Invalid full fixture receipt')
    records, payload, pages, size = map(int, fields[2:])
    expected_payload = (count-1)*(36864 if count == 2048 else VALUE_BYTES)+count*72+(records-count)*97
    if (not count <= records <= 16384 or payload != expected_payload or
            (pages, size) != geometry(records, payload) or (count == 2 and records != 250) or
            (count in (72, 2048) and size <= MEMORY)):
        raise ValueError('Invalid complete full fixture geometry')
    return dict(count=count, root=fields[1], records=records, payload=payload, pages=pages, file_bytes=size)


def parse(raw, mode, count, cache, expected):
    """Require exact independent roots/extents, real graph work, owned queries and complete heap/descriptor retirement."""
    fields = raw.strip().split('\t')
    if (mode not in ('prepare', 'open') or (count, cache) not in CASES or expected['count'] != count or
            len(fields) != 19 or fields[:4] != [mode, str(count), str(cache), expected['root']] or
            any(re.fullmatch(r'0|[1-9][0-9]{0,18}', value) is None for value in fields[4:])):
        raise ValueError('Invalid full native receipt identity')
    names = ('file_bytes', 'pages', 'baseline', 'opened', 'released', 'fd_baseline', 'fd_opened',
             'fd_released', 'read_calls', 'write_calls', 'hash_calls', 'queries', 'peak_rss_bytes',
             'minor_faults', 'major_faults')
    row = dict(zip(names, map(int, fields[4:])))
    if (any(value >= 1 << 63 for value in row.values()) or
            (row['file_bytes'], row['pages']) != (expected['file_bytes'], expected['pages']) or
            not 0 < row['opened']-row['baseline'] < 65536 or row['released'] != row['baseline'] or
            row['fd_baseline'] < 3 or row['fd_released'] != row['fd_baseline'] or
            row['fd_opened']-row['fd_baseline'] != (5 if mode == 'prepare' else 2) or
            row['read_calls'] <= expected['records'] or row['write_calls'] <= expected['records'] or
            row['hash_calls'] <= expected['records'] or row['queries'] != (0 if mode == 'prepare' else 19) or
            not 0 < row['peak_rss_bytes'] < MEMORY):
        raise ValueError('Invalid full native resource witnesses')
    validate_counters({name: row[name] for name in ('peak_rss_bytes', 'minor_faults', 'major_faults')})
    return row


def inputs(compiler, library, binary):
    """Freeze complete production closure, pinned compiler/providers and the independent fixture/measurement helpers."""
    value = panel_identity(compiler, library, SOURCE)
    value['sources'].update(source_hashes([HEADER, Path(__file__), ROOT/'tests/support/full_paged_reference.nim',
        ROOT/'Dockerfile', ROOT/'tests/native/storage_io_observer.c', ROOT/'tests/native/crypto_observer.c',
        *sorted((ROOT/'native/storage_io').glob('*.h'))]))
    observed = BUILD/('libcrypto_observed.dylib' if platform.system() == 'Darwin' else 'libcrypto_observed.so')
    value['observers'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in (observed, BUILD/'storage-io-observer.o')}
    value['binary_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
    return value


def build():
    """Make provisions pinned dependencies before this checked native build; no compiler runs inside pressure."""
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD/'build.json').unlink(missing_ok=True)
    libraries, _, providers = prepare_libraries(BUILD, required={'crypto', 'observer', 'storage_io'})
    compiler, _ = installed()
    flags = ['-I'+str(ROOT/'native/storage_io'), '-I'+str(HEADER.parent),
             '-include'+str(ROOT/'native/storage_io/redirect.h')]
    flags += ['-DRAGNAROK_STORAGE_IO_'+name for name in ('READ', 'WRITE', 'CLOSE', 'FSYNC', 'FLOCK', 'FTRUNCATE')]
    receipt, binary = NativeChecks(BUILD).build(compiler, SOURCE, 'full-paged-native',
        crypto_library=libraries['observer'], native_libraries=(libraries['storage_io'],), cflags=flags)
    receipt.pop('output', None)
    if receipt['exit_code'] != 0:
        raise RuntimeError('Full paged checked build failed: '+receipt['log'])
    record = dict(build=receipt, providers=providers, inputs=inputs(compiler, libraries['crypto'], binary),
                  compiler=str(compiler), library=str(libraries['crypto']), binary=str(binary))
    atomic_text(BUILD/'build.json', json.dumps(record, indent=2)+'\n')
    print('PASS full paged checked probe build: '+str(BUILD/'build.json'), flush=True)


def verify_frozen():
    """Provenance/version inspection runs only outside pressure and rejects any post-build source/provider drift."""
    frozen = json.loads((BUILD/'build.json').read_text())
    compiler, _ = installed()
    library = ROOT/'build/crypto'/('libragnarok_crypto.dylib' if platform.system() == 'Darwin' else 'libragnarok_crypto.so')
    binary = BUILD/'full-paged-native'
    if [frozen['compiler'], frozen['library'], frozen['binary']] != list(map(str, (compiler, library, binary))):
        raise ValueError('Foreign full paged build paths')
    if inputs(compiler, library, binary) != frozen['inputs']:
        raise ValueError('Full paged build inputs changed')
    return frozen


def run_docker(image):
    """Keep Python/fixture maps outside pressure; the persistent private cgroup owns every newly authored selected file/cache."""
    folder = BUILD/('docker-'+uuid.uuid4().hex)
    fixtures = folder/'fixtures'
    fixtures.mkdir(parents=True)
    container = 'ragnarok-full-paged-'+uuid.uuid4().hex
    created = False
    report = dict(status='running', commands=[], runs=[], observer_host=platform.platform(),
                  cases=CASES, memory_bytes=MEMORY, per_value_bytes=VALUE_BYTES,
                  cache_policy='unchanged OS cache; outside-pressure immutable source fixtures; fresh selected files and native execs in one persistent no-swap cgroup')
    def save():
        """Incremental/failure evidence can never inherit a stale successful status."""
        atomic_text(folder/'results.json', json.dumps(report, indent=2)+'\n')
    def execute(args, name, timeout=180, required=True):
        """Preserve exact owned command, logs, deadline and status without printing unbounded native/provider output."""
        started = time.monotonic()
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        (folder/(name+'.log')).write_text(result.stdout+result.stderr)
        report['commands'].append(dict(name=name, command=args, exit_code=result.returncode,
                                      elapsed_seconds=round(time.monotonic()-started, 6), log=name+'.log'))
        save()
        if required and result.returncode != 0:
            raise RuntimeError('Full paged Docker command failed: '+name)
        return result
    def context():
        """Inspect the actual private kernel membership and no-swap controls shared by each measured exec."""
        def read(path):
            return execute(['docker', 'exec', container, 'cat', path], 'kernel-'+str(len(report['commands']))).stdout
        membership, mounts = read('/proc/self/cgroup'), read('/proc/self/mountinfo')
        group = resolve(membership, mounts)
        receipt = dict(membership=membership, mountinfo=mounts, group=group,
                       raw={name: read(group+'/'+name) for name in FILES})
        controls(receipt, MEMORY)
        # Optional kernel peaks are observations, never substitutes for actual max/swap/event controls.
        available = execute(['docker', 'exec', container, 'test', '-f', group+'/memory.peak'],
                            'kernel-peak-'+str(len(report['commands'])), required=False)
        if available.returncode not in (0, 1):
            raise RuntimeError('Kernel peak availability probe failed')
        receipt['peak'] = read(group+'/memory.peak').strip() if available.returncode == 0 else None
        return receipt
    def transfer_hash(owner, path, name):
        """Stream selected bytes into a host64KiB buffer; no resident image or Python observer lives inside pressure."""
        digest = hashlib.sha256()
        with (folder/(name+'.stderr')).open('wb') as error:
            child = subprocess.Popen(['docker', 'exec', owner, 'cat', path], stdout=subprocess.PIPE, stderr=error)
            try:
                started = time.monotonic()
                while True:
                    remaining = 180-(time.monotonic()-started)
                    if remaining <= 0 or not select.select([child.stdout], [], [], remaining)[0]:
                        raise TimeoutError('Full selected transfer deadline')
                    chunk = os.read(child.stdout.fileno(), 65536)
                    if not chunk:
                        break  # EOF belongs to this exact owned transfer, not an inferred absent file.
                    digest.update(chunk)
                code = child.wait(timeout=max(1, 180-(time.monotonic()-started)))
                if code != 0 or (folder/(name+'.stderr')).stat().st_size:
                    raise RuntimeError('Full selected transfer failed: '+name)
            except BaseException:
                child.kill()  # Retire only this still-owned transfer before propagating failure.
                child.wait(timeout=10)
                raise
        return digest.hexdigest()
    def compare_sources(frozen):
        """Only canonical repository paths can bind immutable image input declarations to the actual host checkout."""
        for name, digest in frozen['inputs']['sources'].items():
            relative = PurePosixPath(name)
            if relative.is_absolute() or '..' in relative.parts or str(relative) != name:
                raise ValueError('Invalid full frozen source path')
            if hashlib.sha256((ROOT/name).read_bytes()).hexdigest() != digest:
                raise ValueError('Host/image full source closure differs: '+name)
    save()
    try:
        image_id = execute(['docker', 'image', 'inspect', image, '--format', '{{.Id}}'], 'image').stdout.strip()
        if re.fullmatch('sha256:[0-9a-f]{64}', image_id) is None:
            raise ValueError('Invalid full qualification image identity')
        report['image'] = image_id
        report['target'] = 'linux/amd64'
        report['engine'] = execute(['docker', 'info', '--format', '{{.OSType}}/{{.Architecture}} cgroup={{.CgroupVersion}}'], 'engine').stdout.strip()
        verification = ['docker', 'run', '--rm', '--platform', 'linux/amd64', '--network', 'none',
                        image_id, 'python3', 'tools/storage_full_paged_resources.py', '--verify-only']
        frozen = json.loads(execute(verification, 'frozen').stdout)
        report['build'] = frozen
        compare_sources(frozen)
        expected = {}
        binary = '/src/build/tests/storage-full-paged-resources/full-paged-native'
        for count in COUNTS:
            # Fixture construction exits outside pressure before any bounded writer starts; host source bytes stay immutable afterward.
            native = execute(['docker', 'run', '--rm', '--platform', 'linux/amd64', '--network', 'none',
                '--mount', f'type=bind,source={fixtures},target=/fixtures', image_id,
                binary, 'fixture', '/fixtures/source-'+str(count), str(count), '0'], 'fixture-'+str(count), timeout=1800)
            expected[count] = fixture(native.stdout, count)
            for suffix in ('', '.current'):
                path = fixtures/('source-'+str(count)+suffix)
                path.chmod(0o444)
                with path.open('rb') as stream:
                    expected[count]['sha256'+suffix] = hashlib.file_digest(stream, 'sha256').hexdigest()
        report['fixtures'] = expected
        execute(['docker', 'create', '--platform', 'linux/amd64', '--network', 'none', '--memory', '64m',
            '--memory-swap', '64m', '--mount', f'type=bind,source={fixtures},target=/fixtures,readonly',
            '--name', container, image_id, 'sleep', 'infinity'], 'create')
        created = True
        execute(['docker', 'start', container], 'start')
        report['kernel_before'] = context()
        for count, cache in CASES:
            reference = expected[count]
            path = '/src/build/tests/storage-full-paged-resources/owned-'+uuid.uuid4().hex
            row = dict(count=count, cache=cache, phases=[])
            report['runs'].append(row)
            for mode in ('prepare', 'open'):
                # The writer creates fresh selected/cache inodes inside this same persistent cgroup; source precharging cannot exempt target cache.
                name = f'{count}-{cache}-{mode}'
                native = execute(['docker', 'exec', container, binary, mode, path,
                    '/fixtures/source-'+str(count), str(count), str(cache), reference['root'],
                    str(reference['records']), str(reference['payload'])], name, timeout=1800, required=False)
                phase = dict(mode=mode, raw=native.stdout, exit_code=native.returncode)
                row['phases'].append(phase)
                if native.returncode != 0:
                    raise RuntimeError('Full native resource phase failed: '+name)
                phase['native'] = parse(native.stdout, mode, count, cache, reference)
                phase['kernel'] = context()
                phase['selected'] = {child: transfer_hash(container, path+'/'+child, name+'-'+child)
                    for child in ('CURRENT', 'LOCK', 'paged-0000000000000001.bin')}
                if phase['selected']['CURRENT'] != reference['sha256.current'] or phase['selected']['paged-0000000000000001.bin'] != reference['sha256']:
                    raise ValueError('Selected full bytes differ from independent complete oracle')
                if mode == 'open' and phase['selected'] != row['phases'][0]['selected']:
                    raise ValueError('Strict full reader changed selected bytes')
                save()
        for mode in ('prepare', 'open'):
            for cache in (0, 1):
                # Dataset cardinality/depth changes cannot silently grow the retained native owner beyond a fixed small tolerance.
                retained = [p['native']['opened']-p['native']['baseline'] for r in report['runs'] if r['cache'] == cache
                            for p in r['phases'] if p['mode'] == mode]
                if max(retained)-min(retained) > 256:
                    raise ValueError('Full native retained workspace scales with fixture size/depth')
        for count, reference in expected.items():
            for suffix in ('', '.current'):
                # Final fixed-buffer source hashes also reject host-side fixture drift outside the read-only measured mount.
                with (fixtures/('source-'+str(count)+suffix)).open('rb') as stream:
                    if hashlib.file_digest(stream, 'sha256').hexdigest() != reference['sha256'+suffix]:
                        raise ValueError('Independent full fixture changed during qualification')
        report['kernel_after'] = context()
        final = json.loads(execute(verification, 'frozen-final').stdout)
        if final != frozen:
            raise ValueError('Full frozen build inputs changed')
        compare_sources(frozen)
        report['status'] = 'checks-passed'
        save()
        print('PASS Linux full paged resource panel: '+str(folder/'results.json'), flush=True)
    except BaseException as error:
        report.update(status='failed', error=type(error).__name__+': '+str(error))
        if created:
            # Actual kernel/container state survives a native kill as a separate failure observation.
            report['failure_state'] = execute(['docker', 'inspect', container, '--format', '{{json .State}}'], 'failure-state', required=False).stdout
        save()
        raise
    finally:
        if created:
            execute(['docker', 'rm', '--force', container], 'retire', required=False)  # Only this task-owned container is removed.


def main():
    """Explicit build/verify/Docker modes never silently downgrade a non-Linux host to unqualified local observations."""
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--build-only', action='store_true')
    mode.add_argument('--verify-only', action='store_true')
    mode.add_argument('--docker', metavar='IMAGE')
    args = parser.parse_args()
    if args.build_only:
        build()
    elif args.verify_only:
        print(json.dumps(verify_frozen(), sort_keys=True))
    else:
        run_docker(args.docker)


if __name__ == '__main__':
    main()
