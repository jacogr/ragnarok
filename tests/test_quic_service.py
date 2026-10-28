#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Persistent-engine multi-peer regression, with bounded cleanup and ownership checks.

Exposes check_cleanup, wait_service, service for the verification harness.
"""
from functools import partial
import json
import os
import re
import socket
import subprocess
import time
from test_quic import application_binaries, BUILD, THREAD_BASELINES
from test_quic_soak import resources, check_growth


# Check after engine destruction: cached transport allocations must no longer inflate the live baseline.
def check_cleanup(language, text):
    clean = re.findall(r'^SERVICE_CLEAN (\d+) (\d+)$', text, re.M)
    assert len(clean) == 1, ('missing or duplicate cleanup observation', clean)
    before, after = map(int, clean[0])
    assert language in ('nim',) and after <= before + 65536, clean


# Keep one listener PID/engine alive while observing bounded resource use and native application markers.
def wait_service(server, log, predicate, peaks, seconds=10, thread_limit=1):
    deadline = time.monotonic() + seconds
    # A failed/dead listener cannot satisfy a later observation using stale log output.
    while True:
        text = log.read_text()
        assert server.poll() is None, ('listener exited', server.returncode, text[-4000:])
        sample = resources(server.pid)
        assert 1 <= sample['threads'] <= thread_limit and sample['rss_bytes'] < 256 * 1024 * 1024, (sample, thread_limit)
        # Readiness/authentication establishes the one-dispatcher thread baseline.
        if any(line == 'READY' or line == 'AUTH_OK' or line.startswith('MESH_READY ') for line in text.splitlines()):
            assert sample['threads'] == thread_limit, ('changed fixed runtime thread count', sample, thread_limit)
        # Aggregate high-water observations without inspecting descriptor contents or private keys.
        for metric, value in sample.items():
            peaks[metric] = max(peaks.get(metric, 0), value)
        if predicate(text):
            return text
        assert time.monotonic() < deadline, ('service observation timed out', text[-4000:])
        time.sleep(0.02)


# Exercise the Nim listener with independent client identities and reconnect waves.
def service(language, folder, rounds, warmup, *, binaries=None, directory=None):
    # Compiler-specific binaries and logs preserve the same workload without overwriting normal build products.
    binaries = application_binaries(binaries)
    thread_limit = THREAD_BASELINES[language]
    # A fixed startup pool is measured separately; native streams may never add threads.
    wait = partial(wait_service, thread_limit=thread_limit)
    directory = BUILD / 'service' / language if directory is None else directory
    directory.mkdir(parents=True, exist_ok=True)
    stop = directory / f'stop-{time.time_ns()}'
    log = directory / 'server.log'
    idle, peaks, children, handles = [], {}, [], []
    # The ephemeral reservation is released before binding; readiness checks expose any competing bind race.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    command = [str(binaries[language]), 'server', '--net-port', str(port), '--net-cert', str(folder / 'a.cert.pem'),
               '--net-key', str(folder / 'a.key.pem'), '--net-peer-key', '-', '--net-alpn', 'jamnp-s/1/00000000', '--net-timeout-ms', '120000', '--net-mode', 'service']
    handle = log.open('w')
    server = subprocess.Popen(command, env={**os.environ, 'RAGNAROK_SERVICE_STOP': str(stop)},
                              stdout=handle, stderr=subprocess.STDOUT)
    started = time.monotonic()

    # Each dial uses a fresh client process/connection; only the server's engine is persistent in this round.
    def client(iteration, name, implementation, identity, mode, alpn='jamnp-s/1/00000000'):
        path = directory / f'{iteration}-{name}.log'
        output = path.open('w')
        handles.append(output)
        arguments = [str(binaries[implementation]), 'client', '--net-port', str(port),
                     '--net-cert', str(folder / f'{identity}.cert.pem'), '--net-key', str(folder / f'{identity}.key.pem'),
                     '--net-peer-key', str(folder / 'a.pub'), '--net-alpn', alpn, '--net-timeout-ms', '5000', '--net-mode', mode]
        process = subprocess.Popen(arguments, stdout=output, stderr=subprocess.STDOUT)
        children.append(process)
        return process, path

    accepted = 0
    try:
        wait(server, log, lambda text: 'READY\n' in text, peaks)
        # Repeated waves use the same identities but new connections, proving reconnect after retirement.
        for iteration in range(rounds):
            before = log.read_text()
            blocked = before.count('BACKPRESSURE\n')
            isolated = before.count('ISOLATED_HEALTHY\n')
            mixed = [client(iteration, 'mixed-primary', 'nim', 'b', 'mixed'),
                     client(iteration, 'mixed-secondary', 'nim', 'c', 'mixed')]
            wait(server, log, lambda text: text.count('BACKPRESSURE\n') >= blocked + 2, peaks)
            # TLS rejection overlaps healthy peers and must not terminate or poison the shared listener.
            rejected = client(iteration, 'rejected', 'nim',
                              'wrong-san' if iteration % 2 == 0 else 'b', 'clean',
                              'jamnp-s/1/00000000' if iteration % 2 == 0 else 'jamnp-s/1/11111111')
            crash = None
            # Kill an authenticated peer at the first and final wave; the transport's idle deadline retires it.
            if iteration in (0, rounds - 1):
                crash = client(iteration, 'crashed', 'nim', 'e', 'mixed')
                wait(server, log, lambda text: re.search(r'^PEERS [3-9]\d*$', text[len(before):], re.M), peaks)
                crash[0].kill()
                crash[0].wait(timeout=5)
                accepted += 1
            # Separate healthy connections must complete while the mixed peers own parked writes.
            healthy = [client(iteration, 'healthy-primary', 'nim', 'd', 'clean'),
                       client(iteration, 'healthy-secondary', 'nim', 'e', 'clean')]
            wait(server, log, lambda text: text.count('ISOLATED_HEALTHY\n') > isolated, peaks)
            # Exact client outcomes distinguish framed exchanges from merely authenticated TLS sessions.
            for process, path in healthy + mixed:
                assert process.wait(timeout=8) == 0, (path.name, path.read_text())
                text = path.read_text()
                assert text.count('EXCHANGE_OK 8\n') == 1, (path.name, text)
                if (process, path) in mixed:
                    assert text.count('HEALTHY_OK\n') == 5 and text.count('EXPECTED_REJECT\n') == 2 and text.count('CANCEL_OK\n') == 1, text
            assert rejected[0].wait(timeout=8) == 2, rejected[1].read_text()
            assert 'EXCHANGE_OK' not in rejected[1].read_text(), rejected[1].read_text()
            accepted += 4
            # Native idle markers require zero retained connections AND zero live native-language stream slots.
            text = wait(server, log, lambda text: f'SERVICE_IDLE {accepted} {accepted} ' in text, peaks)
            matches = re.findall(rf'^SERVICE_IDLE {accepted} {accepted} (\d+)(?: (\d+))?$', text, re.M)
            assert len(matches) == 1, ('missing or duplicate idle observation', text[-2000:])
            sample = resources(server.pid)
            sample['thread_baseline'] = thread_limit
            sample['allocated_bytes'] = int(matches[0][0])
            idle.append(sample)
            print(f'{language} service: {iteration + 1}/{rounds} waves, {accepted} retired connections', flush=True)
        growth = check_growth(idle, warmup, language)
        text = log.read_text()
        assert text.count('REQUEST_TIMEOUT\n') >= rounds * 2, text[-4000:]
        assert text.count('SERVER_HEALTHY\n') >= rounds * 26, text[-4000:]
        # Shut down only at the fully retired barrier and require deferred owner cleanup to complete normally.
        stop.touch()
        assert server.wait(timeout=5) == 0, log.read_text()[-4000:]
        summary = re.findall(r'^SERVICE_DONE (\d+) (\d+) (\d+)$', log.read_text(), re.M)
        assert len(summary) == 1 and tuple(map(int, summary[0][:2])) == (accepted, accepted), summary
        peak = int(summary[0][2])
        assert peak >= 3, ('no actual multi-peer overlap', summary)
        check_cleanup(language, log.read_text())
        return {'language': language, 'thread_baseline': thread_limit, 'persistent_server_pid': server.pid, 'rounds': rounds,
                'accepted_and_retired_connections': accepted, 'peak_connections': peak,
                'isolated_healthy_outcomes': text.count('ISOLATED_HEALTHY\n'),
                'elapsed_seconds': time.monotonic() - started, 'peaks': peaks, 'idle': idle, 'growth': growth}
    finally:
        # Always retain diagnostics and retire children, including on an assertion or harness timeout.
        (directory / 'resources.json').write_text(json.dumps({'peaks': peaks, 'idle': idle}, indent=2) + '\n')
        for process in [server, *children]:
            if process.poll() is None:
                process.kill()
            process.wait()
        for output in [handle, *handles]:
            output.close()
