#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Bounded same-process QUIC lifecycle soak; share fixtures/builds, never native protocol code.

Exposes resources, wait_marker, check_growth, pairing for the verification harness.
"""
import json
import os
from pathlib import Path
import platform
import re
import socket
import subprocess
import time
from test_quic import application_binaries, BUILD, thread_count, THREAD_BASELINES


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
def wait_marker(processes, logs, role, marker, peaks, seconds=8, occurrences=1, thread_limits=None):
    deadline = time.monotonic() + seconds
    # Count complete marker lines: diagnostic output may occur between lifecycle events.
    # A previous READY cannot release the next session's dial; each round needs its own occurrence.
    while logs[role].read_text().splitlines().count(marker) < occurrences:
        assert time.monotonic() < deadline, (role, marker, 'deadline', logs[role].read_text()[-2000:])
        for name, process in processes.items():
            assert process.poll() is None, (name, process.returncode, logs[name].read_text()[-2000:])
            sample = resources(process.pid)
            # Active caps detect runaway storage and any hidden thread-per-stream substitution.
            expected_threads = 1 if thread_limits is None else thread_limits[name]
            assert 1 <= sample['threads'] <= expected_threads and sample['rss_bytes'] < 256 * 1024 * 1024, (name, sample, expected_threads)
            # Readiness/authentication establishes the one-dispatcher thread baseline.
            if any(line == 'READY' or line == 'AUTH_OK' or line.startswith('MESH_READY ') for line in logs[name].read_text().splitlines()):
                assert sample['threads'] == expected_threads, ('changed fixed runtime thread count', sample, expected_threads)
            # Retain per-role high-water observations without holding OS descriptor contents.
            for metric, value in sample.items():
                peaks[name][metric] = max(peaks[name].get(metric, 0), value)
        time.sleep(0.02)


# Scope is part of the observation: process malloc includes retained transport pools and SDK storage.
ALLOCATION_SCOPES = {'nim': 'language allocator'}
# Preserve the application-owner budget; aggregate malloc uses the existing aggregate RSS growth budget.
IDLE_ALLOCATION_LIMITS = {'nim': 64 * 1024}


# Compare post-warmup observations using the explicitly identified counter; unknown peers fail closed.
def check_growth(samples, warmup, language, *, retained_engine=True):
    retained = samples[warmup:]
    assert len(retained) >= 8, 'Need at least eight post-warmup lifecycle samples'
    rss = [sample['rss_bytes'] for sample in retained]
    descriptors = [sample['descriptors'] for sample in retained]
    # Fixed budgets are deliberately reported, rather than describing this finite run as leak freedom.
    assert max(rss) - min(rss) <= 16 * 1024 * 1024, ('idle RSS growth exceeds 16 MiB', rss)
    assert max(descriptors) - min(descriptors) <= 2, ('idle descriptor growth exceeds two', descriptors)
    assert all(sample['threads'] == sample.get('thread_baseline', 1) for sample in retained), retained
    allocated = [sample['allocated_bytes'] for sample in retained]
    limit = IDLE_ALLOCATION_LIMITS[language]
    if not retained_engine:
        limit = 64 * 1024
    assert max(allocated) - min(allocated) <= limit, ('idle allocation growth exceeds scoped budget', language, limit, allocated)
    return {'idle_rss_range_bytes': max(rss) - min(rss),
            'idle_descriptor_range': max(descriptors) - min(descriptors),
            'idle_allocation_range_bytes': max(allocated) - min(allocated),
            'allocation_scope': ALLOCATION_SCOPES[language], 'idle_allocation_limit_bytes': limit,
            'retained_engine': retained_engine}


# Run both persistent native processes through the same mixed workload, gating each lifecycle for clean idle samples.
def pairing(server_language, client_language, folder, rounds, warmup, *, binaries=None, directory=None):
    name = f'{server_language}-{client_language}'
    # Isolated compiler builds reuse this exact lifecycle schedule and all original resource limits.
    binaries = application_binaries(binaries)
    directory = BUILD / 'soak' / name if directory is None else directory
    directory.mkdir(parents=True, exist_ok=True)
    gate = directory / f'gate-{time.time_ns()}'
    gate.mkdir()
    logs = {role: directory / f'{role}.log' for role in ('server', 'client')}
    processes, handles = {}, {}
    thread_limits = {'server': THREAD_BASELINES[server_language], 'client': THREAD_BASELINES[client_language]}
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
            command = [str(binaries[language]), role, '--net-port', str(port),
                       '--net-cert', str(folder / f'{identity}.cert.pem'), '--net-key', str(folder / f'{identity}.key.pem'),
                       '--net-peer-key', '-' if role == 'server' else str(folder / 'a.pub'), '--net-alpn', 'jamnp-s/1/00000000', '--net-timeout-ms', '5000', '--net-mode', 'soak']
            environment = {**os.environ, 'RAGNAROK_SOAK_ROUNDS': str(rounds), 'RAGNAROK_SOAK_GATE': str(gate)}
            processes[role] = subprocess.Popen(command, env=environment, stdout=handles[role], stderr=subprocess.STDOUT)
        for iteration in range(rounds):
            # Bind the server first, then release the client's dial against its announced listener.
            (gate / f'server-{iteration}').touch()
            wait_marker(processes, logs, 'server', 'READY', peaks, occurrences=iteration + 1, thread_limits=thread_limits)
            (gate / f'client-{iteration}').touch()
            for role in logs:
                wait_marker(processes, logs, role, f'SESSION_DONE {iteration}', peaks, thread_limits=thread_limits)
            # Both transports, UDP sockets and callback owners have retired before this observation.
            for role, process in processes.items():
                sample = resources(process.pid)
                allocation = re.findall(r'ALLOC_BYTES (\d+)', logs[role].read_text())
                assert len(allocation) == iteration + 1, (role, 'missing allocator observation')
                sample['allocated_bytes'] = int(allocation[-1])
                sample['thread_baseline'] = thread_limits[role]
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
        growth = {role: check_growth(samples, warmup, server_language if role == 'server' else client_language, retained_engine=False) for role, samples in idle.items()}
        # Release the final idle barrier and require normal cleanup-driven exits.
        for role in logs:
            (gate / f'{role}-{rounds}').touch()
        for role, process in processes.items():
            assert process.wait(timeout=5) == 0, (name, role, logs[role].read_text()[-2000:])
        return {'server': server_language, 'client': client_language, 'rounds': rounds, 'elapsed_seconds': time.monotonic() - started, 'thread_baselines': thread_limits, 'allocation_scope': {'nim': 'language allocator'}, 'peaks': peaks, 'idle': idle, 'growth': growth}
    finally:
        (directory / 'resources.json').write_text(json.dumps({'peaks': peaks, 'idle': idle}, indent=2) + '\n')
        # A failed assertion must not leave a UDP peer or parked event loop running.
        for process in processes.values():
            if process.poll() is None:
                process.kill()
            process.wait()
        for handle in handles.values():
            handle.close()
