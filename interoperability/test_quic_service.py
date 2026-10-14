#!/usr/bin/env python3
"""Persistent-engine multi-peer regression, distinct from throughput benchmarking."""
import argparse
import json
import os
import platform
import re
import socket
import subprocess
import time
from test_quic import BUILD, build_peers, dependencies, fixtures
from test_quic_soak import resources, check_growth


# Keep one listener PID/engine alive while observing bounded resource use and native application markers.
def wait_service(server, log, predicate, peaks, seconds=10):
    deadline = time.monotonic() + seconds
    # A failed/dead listener cannot satisfy a later observation using stale log output.
    while True:
        text = log.read_text()
        assert server.poll() is None, ('listener exited', server.returncode, text[-4000:])
        sample = resources(server.pid)
        assert sample['threads'] == 1 and sample['rss_bytes'] < 256 * 1024 * 1024, sample
        # Aggregate high-water observations without inspecting descriptor contents or private keys.
        for metric, value in sample.items():
            peaks[metric] = max(peaks.get(metric, 0), value)
        if predicate(text):
            return text
        assert time.monotonic() < deadline, ('service observation timed out', text[-4000:])
        time.sleep(0.02)


# Exercise one language's listener with both client languages, independent identities and reconnect waves.
def service(language, folder, rounds, warmup):
    directory = BUILD / 'service' / language
    directory.mkdir(parents=True, exist_ok=True)
    stop = directory / f'stop-{time.time_ns()}'
    log = directory / 'server.log'
    idle, peaks, children, handles = [], {}, [], []
    # The ephemeral reservation is released before binding; readiness checks expose any competing bind race.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    command = [str(BUILD / f'{language}-peer'), 'server', str(port), str(folder / 'a.cert.pem'),
               str(folder / 'a.key.pem'), '-', 'jamnp-s/1/00000000', '120000', 'service']
    handle = log.open('w')
    server = subprocess.Popen(command, env={**os.environ, 'RAGNAROK_SERVICE_STOP': str(stop)},
                              stdout=handle, stderr=subprocess.STDOUT)
    started = time.monotonic()

    # Each dial uses a fresh client process/connection; only the server's engine is persistent in this round.
    def client(iteration, name, implementation, identity, mode, alpn='jamnp-s/1/00000000'):
        path = directory / f'{iteration}-{name}.log'
        output = path.open('w')
        handles.append(output)
        arguments = [str(BUILD / f'{implementation}-peer'), 'client', str(port),
                     str(folder / f'{identity}.cert.pem'), str(folder / f'{identity}.key.pem'),
                     str(folder / 'a.pub'), alpn, '5000', mode]
        process = subprocess.Popen(arguments, stdout=output, stderr=subprocess.STDOUT)
        children.append(process)
        return process, path

    accepted = 0
    try:
        wait_service(server, log, lambda text: 'READY\n' in text, peaks)
        # Repeated waves use the same identities but new connections, proving reconnect after retirement.
        for iteration in range(rounds):
            before = log.read_text()
            blocked = before.count('BACKPRESSURE\n')
            isolated = before.count('ISOLATED_HEALTHY\n')
            mixed = [client(iteration, 'mixed-nim', 'nim', 'b', 'mixed'),
                     client(iteration, 'mixed-odin', 'odin', 'c', 'mixed')]
            wait_service(server, log, lambda text: text.count('BACKPRESSURE\n') >= blocked + 2, peaks)
            # TLS rejection overlaps healthy peers and must not terminate or poison the shared listener.
            rejected = client(iteration, 'rejected', 'nim' if iteration % 2 == 0 else 'odin',
                              'wrong-san' if iteration % 2 == 0 else 'b', 'clean',
                              'jamnp-s/1/00000000' if iteration % 2 == 0 else 'jamnp-s/1/11111111')
            crash = None
            # Kill an authenticated peer at the first and final wave; the transport's idle deadline retires it.
            if iteration in (0, rounds - 1):
                crash = client(iteration, 'crashed', 'odin' if language == 'nim' else 'nim', 'e', 'mixed')
                wait_service(server, log, lambda text: re.search(r'^PEERS [3-9]\d*$', text[len(before):], re.M), peaks)
                crash[0].kill()
                crash[0].wait(timeout=5)
                accepted += 1
            # Separate healthy connections must complete while the mixed peers own parked writes.
            healthy = [client(iteration, 'healthy-nim', 'nim', 'd', 'clean'),
                       client(iteration, 'healthy-odin', 'odin', 'e', 'clean')]
            wait_service(server, log, lambda text: text.count('ISOLATED_HEALTHY\n') > isolated, peaks)
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
            text = wait_service(server, log, lambda text: f'SERVICE_IDLE {accepted} {accepted} ' in text, peaks)
            matches = re.findall(rf'^SERVICE_IDLE {accepted} {accepted} (\d+)(?: (\d+))?$', text, re.M)
            assert len(matches) == 1, ('missing or duplicate idle observation', text[-2000:])
            sample = resources(server.pid)
            sample['allocated_bytes'] = int(matches[0][0])
            # Odin retains only one receive and one timer while the service stays live; cancellation drains both at exit.
            if language == 'odin':
                assert int(matches[0][1]) == 2, ('retained event-loop operations', matches)
            idle.append(sample)
            print(f'{language} service: {iteration + 1}/{rounds} waves, {accepted} retired connections', flush=True)
        growth = check_growth(idle, warmup)
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
        if language == 'nim':
            clean = re.findall(r'^SERVICE_CLEAN (\d+) (\d+)$', log.read_text(), re.M)
            assert len(clean) == 1 and int(clean[0][1]) <= int(clean[0][0]) + 65536, clean
        if language == 'odin':
            assert 'SERVICE_CLEAN 0 0\n' in log.read_text(), log.read_text()[-4000:]
        return {'language': language, 'persistent_server_pid': server.pid, 'rounds': rounds,
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


# Keep build provenance and finite resource limits explicit; this test produces no language speed ranking.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true')
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--rounds', type=int, default=16)
    parser.add_argument('--warmup', type=int, default=4)
    args = parser.parse_args()
    assert 12 <= args.rounds <= 32 and 0 <= args.warmup <= args.rounds - 8, 'Invalid bounded service extent'
    BUILD.mkdir(parents=True, exist_ok=True)
    if not args.skip_build:
        build_peers(dependencies(args.fetch))
    folder = fixtures()
    output = BUILD / 'service/results.json'
    output.parent.mkdir(exist_ok=True)
    report = {'platform': platform.platform(), 'rounds': args.rounds, 'warmup': args.warmup,
              'complete': False, 'persistent_client_engines': False,
              'limits': {'active_rss_bytes': 256 * 1024 * 1024, 'threads': 1,
                         'idle_rss_range_bytes': 16 * 1024 * 1024, 'idle_descriptor_range': 2,
                         'idle_allocation_range_bytes': 65536}, 'servers': []}
    try:
        # Both persistent listeners receive the same mix of independent Nim and Odin clients.
        for language in ('nim', 'odin'):
            report['servers'].append(service(language, folder, args.rounds, args.warmup))
            output.write_text(json.dumps(report, indent=2) + '\n')
    except Exception as error:
        report['failure'] = str(error)
        output.write_text(json.dumps(report, indent=2) + '\n')
        raise
    report['complete'] = True
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(f'PASS persistent QUIC: {2 * args.rounds} multi-peer waves; two engine lifetimes', flush=True)


# Importing this harness neither builds nor launches network peers.
if __name__ == '__main__':
    main()
