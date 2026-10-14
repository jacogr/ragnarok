#!/usr/bin/env python3
"""Bounded same-process QUIC lifecycle soak; share fixtures/builds, never native protocol code."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import socket
import subprocess
import time
from test_quic import BUILD, build_peers, dependencies, fixtures, thread_count


# Observe resident memory, OS threads and open descriptors without reading their contents.
def resources(pid):
    if platform.system() == 'Linux':
        status = Path(f'/proc/{pid}/status').read_text()
        rss = int(re.search(r'^VmRSS:\s+(\d+)', status, re.M)[1]) * 1024
        descriptors = len(list(Path(f'/proc/{pid}/fd').iterdir()))
    else:
        # macOS observations are a local smoke/soak result; Linux CI uses procfs above.
        rss = int(subprocess.check_output(['ps', '-o', 'rss=', '-p', str(pid)], text=True)) * 1024
        files = subprocess.run(['lsof', '-a', '-p', str(pid), '-Ff'], text=True, capture_output=True, check=True).stdout
        descriptors = sum(bool(re.fullmatch(r'f\d+', line)) for line in files.splitlines())
    return {'rss_bytes': rss, 'threads': thread_count(pid), 'descriptors': descriptors}


# Wait for explicit lifecycle markers, sampling live resources and preserving a hard per-session ceiling.
def wait_marker(processes, logs, role, marker, peaks, seconds=8, occurrences=1):
    deadline = time.monotonic() + seconds
    # Count complete marker lines: diagnostic output may occur between lifecycle events.
    # A previous READY cannot release the next session's dial; each round needs its own occurrence.
    while logs[role].read_text().splitlines().count(marker) < occurrences:
        assert time.monotonic() < deadline, (role, marker, 'deadline', logs[role].read_text()[-2000:])
        for name, process in processes.items():
            assert process.poll() is None, (name, process.returncode, logs[name].read_text()[-2000:])
            sample = resources(process.pid)
            # Active caps detect runaway storage and any hidden thread-per-stream substitution.
            assert sample['threads'] == 1 and sample['rss_bytes'] < 256 * 1024 * 1024, (name, sample)
            # Retain per-role high-water observations without holding OS descriptor contents.
            for metric, value in sample.items():
                peaks[name][metric] = max(peaks[name].get(metric, 0), value)
        time.sleep(0.02)


# Compare post-warmup idle observations so allocator high-water behaviour is not mistaken for per-session leakage.
def check_growth(samples, warmup):
    retained = samples[warmup:]
    assert len(retained) >= 8, 'Need at least eight post-warmup lifecycle samples'
    rss = [sample['rss_bytes'] for sample in retained]
    descriptors = [sample['descriptors'] for sample in retained]
    # Fixed budgets are deliberately reported, rather than describing this finite run as leak freedom.
    assert max(rss) - min(rss) <= 16 * 1024 * 1024, ('idle RSS growth exceeds 16 MiB', rss)
    assert max(descriptors) - min(descriptors) <= 2, ('idle descriptor growth exceeds two', descriptors)
    assert all(sample['threads'] == 1 for sample in retained), retained
    # Language allocator counters exclude transport C allocations; RSS above covers their aggregate footprint.
    allocated = [sample['allocated_bytes'] for sample in retained]
    assert max(allocated) - min(allocated) <= 64 * 1024, ('live allocation growth exceeds 64 KiB', allocated)
    return {'idle_rss_range_bytes': max(rss) - min(rss),
            'idle_descriptor_range': max(descriptors) - min(descriptors),
            'idle_allocation_range_bytes': max(allocated) - min(allocated)}


# Run both persistent native processes through the same mixed workload, gating each lifecycle for clean idle samples.
def pairing(server_language, client_language, folder, rounds, warmup):
    name = f'{server_language}-{client_language}'
    directory = BUILD / 'soak' / name
    directory.mkdir(parents=True, exist_ok=True)
    gate = directory / f'gate-{time.time_ns()}'
    gate.mkdir()
    logs = {role: directory / f'{role}.log' for role in ('server', 'client')}
    processes, handles = {}, {}
    peaks = {role: {} for role in logs}
    idle = {role: [] for role in logs}
    started = time.monotonic()
    # Reserve a localhost UDP port; readiness and exit checks make bind races explicit failures.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    try:
        # These processes remain alive across every round; restarting them would conceal retained allocations.
        for role, language, identity in (('server', server_language, 'a'), ('client', client_language, 'b')):
            handles[role] = logs[role].open('w')
            command = [str(BUILD / f'{language}-peer'), role, str(port),
                       str(folder / f'{identity}.cert.pem'), str(folder / f'{identity}.key.pem'),
                       '-' if role == 'server' else str(folder / 'a.pub'), 'jamnp-s/1/00000000', '5000', 'soak']
            environment = {**os.environ, 'RAGNAROK_SOAK_ROUNDS': str(rounds), 'RAGNAROK_SOAK_GATE': str(gate)}
            processes[role] = subprocess.Popen(command, env=environment, stdout=handles[role], stderr=subprocess.STDOUT)
        for iteration in range(rounds):
            # Bind the server first, then release the client's dial against its announced listener.
            (gate / f'server-{iteration}').touch()
            wait_marker(processes, logs, 'server', 'READY', peaks, occurrences=iteration + 1)
            (gate / f'client-{iteration}').touch()
            for role in logs:
                wait_marker(processes, logs, role, f'SESSION_DONE {iteration}', peaks)
            # Both transports, UDP sockets and callback owners have retired before this observation.
            for role, process in processes.items():
                sample = resources(process.pid)
                allocation = re.findall(r'ALLOC_BYTES (\d+)', logs[role].read_text())
                assert len(allocation) == iteration + 1, (role, 'missing allocator observation')
                sample['allocated_bytes'] = int(allocation[-1])
                idle[role].append(sample)
            if (iteration + 1) % 10 == 0:
                print(f'{name}: {iteration + 1}/{rounds} sessions', flush=True)
        text = {role: path.read_text() for role, path in logs.items()}
        # Native markers prove application outcomes, not merely a surviving process or successful TLS handshake.
        assert text['client'].count('HEALTHY_OK\n') == rounds * 5, name
        assert text['client'].count('CANCEL_OK\n') == rounds, name
        assert text['client'].count('EXPECTED_REJECT\n') == rounds * 2, name
        assert text['server'].count('SERVER_HEALTHY\n') == rounds * 5, name
        assert text['server'].count('STREAM_REJECTED\n') == rounds * 3, name
        assert text['server'].count('REQUEST_TIMEOUT\n') == rounds, name
        assert text['server'].count('BACKPRESSURE\n') >= rounds, name
        for role in logs:
            assert text[role].count('EXCHANGE_OK 8\n') == rounds, (name, role)
        growth = {role: check_growth(samples, warmup) for role, samples in idle.items()}
        # Release the final idle barrier and require normal cleanup-driven exits.
        for role in logs:
            (gate / f'{role}-{rounds}').touch()
        for role, process in processes.items():
            assert process.wait(timeout=5) == 0, (name, role, logs[role].read_text()[-2000:])
        return {'server': server_language, 'client': client_language, 'rounds': rounds,
                'elapsed_seconds': time.monotonic() - started, 'peaks': peaks, 'idle': idle, 'growth': growth}
    finally:
        (directory / 'resources.json').write_text(json.dumps({'peaks': peaks, 'idle': idle}, indent=2) + '\n')
        # A failed assertion must not leave a UDP peer or parked event loop running.
        for process in processes.values():
            if process.poll() is None:
                process.kill()
            process.wait()
        for handle in handles.values():
            handle.close()


# Keep sustained correctness distinct from performance benchmarking and the existing one-shot rejection matrix.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true')
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--rounds', type=int, default=40)
    parser.add_argument('--warmup', type=int, default=8)
    args = parser.parse_args()
    assert 16 <= args.rounds <= 1000 and 0 <= args.warmup <= args.rounds - 8, 'Invalid bounded soak extent'
    BUILD.mkdir(parents=True, exist_ok=True)
    # Reuse only explicitly requested binaries; default execution recompiles the current native sources.
    if not args.skip_build:
        build_peers(dependencies(args.fetch))
    # Independently verify the large fixture/map key rather than trusting duplicated native constants.
    fixture = bytes(i % 251 for i in range(1024 * 1024))
    assert hashlib.blake2b(fixture, digest_size=32).hexdigest() == '8a5a7a9dc3cf203ed374b0a1eea930601ad2acbfe2b4bc62cf83de4ee536528b'
    folder = fixtures()
    report = {'platform': platform.platform(), 'rounds': args.rounds, 'warmup': args.warmup,
              'complete': False, 'limits': {'active_rss_bytes': 256 * 1024 * 1024, 'idle_rss_range_bytes': 16 * 1024 * 1024,
                         'idle_descriptor_range': 2, 'idle_allocation_range_bytes': 64 * 1024, 'threads': 1}, 'pairings': []}
    output = BUILD / 'soak/results.json'
    output.parent.mkdir(exist_ok=True)
    try:
        # Sequential pairings avoid unrelated host load confounding resource observations.
        for server, client in (('nim', 'nim'), ('odin', 'odin'), ('nim', 'odin'), ('odin', 'nim')):
            report['pairings'].append(pairing(server, client, folder, args.rounds, args.warmup))
            output.write_text(json.dumps(report, indent=2) + '\n')
    except Exception as error:
        report['failure'] = str(error)
        output.write_text(json.dumps(report, indent=2) + '\n')
        raise
    report['complete'] = True
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(f'PASS QUIC soak: {4 * args.rounds} same-process sessions; five healthy and three adversarial streams/session', flush=True)


# Importing helpers performs no build, certificate generation or network operation.
if __name__ == '__main__':
    main()
