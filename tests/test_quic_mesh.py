#!/usr/bin/env python3
"""Retained two-peer IPv6 engines, duplicate arbitration, fallback dial and bidirectional CE 143 regression."""
import json
import os
import socket
import subprocess
import time
from test_quic import BUILD, THREAD_BASELINES
from test_quic_soak import resources, check_growth


# Reserve two distinct IPv6 UDP listener ports until both have been selected; readiness exposes bind races.
def ports():
    with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as a, socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as b:
        a.bind(('::1', 0)); b.bind(('::1', 0))
        return a.getsockname()[1], b.getsockname()[1]


# Verify the spec expression independently, using Python byte-string ordering and arbitrary-precision bit extraction.
def preferred(local, remote):
    assert len(local) == len(remote) == 32 and local != remote
    return bool(((local[-1] >> 7) ^ (remote[-1] >> 7)) ^ (local < remote))


# Wait for both peers' explicit markers, checking bounded resources even while no application messages are pending.
def observe(processes, logs, marker, peaks, seconds=15, thread_limits=None):
    deadline = time.monotonic() + seconds
    # Never let stale logs or a crashed peer satisfy a subsequent lifecycle barrier.
    while True:
        texts = {role: path.read_text() for role, path in logs.items()}
        for role, process in processes.items():
            assert process.poll() is None, (role, process.returncode, texts[role][-4000:])
            sample = resources(process.pid)
            expected_threads = 1 if thread_limits is None else thread_limits[role]
            assert 1 <= sample['threads'] <= expected_threads and sample['rss_bytes'] < 256 * 1024 * 1024, (role, sample, expected_threads)
            # Readiness/authentication establishes the one-dispatcher thread baseline.
            if any(line == 'READY' or line == 'AUTH_OK' or line.startswith('MESH_READY ') for line in texts[role].splitlines()):
                assert sample['threads'] == expected_threads, ('changed fixed runtime thread count', sample, expected_threads)
            for metric, value in sample.items():
                peaks[role][metric] = max(peaks[role].get(metric, 0), value)
        if all(any(line.startswith(marker) for line in text.splitlines()) for text in texts.values()):
            return texts
        assert time.monotonic() < deadline, (marker, texts)
        time.sleep(0.02)


# Keep both logical peer processes and all four role engines alive for the complete externally gated workload.
def pairing(languages, folder, rounds, warmup, bad_pin=False, *, binaries=None, directory=None, telemetry=None, checkpoint=None):
    # Compiler-specific binary/log paths preserve the same retained engine and gate schedules.
    binaries = binaries or {name: BUILD / f'{name}-peer' for name in THREAD_BASELINES}
    name = '-'.join(languages) + ('-bad-pin' if bad_pin else '')
    directory = BUILD / 'mesh' / name if directory is None else directory
    directory.mkdir(parents=True, exist_ok=True)
    gate = directory / f'gate-{time.time_ns()}'
    gate.mkdir()
    logs = {role: directory / f'{role}.log' for role in ('a', 'b')}
    processes, handles = {}, {}
    thread_limits = dict(zip(logs, (THREAD_BASELINES[language] for language in languages)))
    peaks = {role: {} for role in logs}
    idle = {role: [] for role in logs}
    identities = {role: (folder / f'{role}.pub').read_bytes() for role in logs}
    decisions = {'a': preferred(identities['a'], identities['b']), 'b': preferred(identities['b'], identities['a'])}
    local_ports = ports()
    started = time.monotonic()
    try:
        # Each process owns one listener socket and one persistent outgoing socket, both IPv6-only loopback endpoints.
        for index, (role, language) in enumerate(zip(logs, languages)):
            other = 'b' if role == 'a' else 'a'
            remote_pin = 'c' if bad_pin and role == 'a' else other
            command = [str(binaries[language]), 'mesh', str(local_ports[index]), str(local_ports[1-index]),
                       str(folder / f'{role}.cert.pem'), str(folder / f'{role}.key.pem'),
                       str(folder / f'{role}.pub'), str(folder / f'{remote_pin}.pub'), 'jamnp-s/1/00000000', str(gate)]
            if telemetry is not None:
                # Optional collector controls exercise the real trailing CLI without changing mesh policy.
                command += ['--chain', str(telemetry['chain']), '--telemetry', telemetry[role]]
            handles[role] = logs[role].open('w')
            processes[role] = subprocess.Popen(command, stdout=handles[role], stderr=subprocess.STDOUT,
                env={**os.environ, 'RAGNAROK_MESH_ROUNDS': str(rounds), 'RAGNAROK_MESH_FALLBACK': '0' if bad_pin else '1'})
        texts = observe(processes, logs, 'MESH_READY ', peaks, thread_limits=thread_limits)
        for role, text in texts.items():
            if not bad_pin:
                assert f'MESH_READY {int(decisions[role])}' in text.splitlines(), (role, decisions, text)
        if checkpoint is not None:
            checkpoint(-1) # Collector setup runs only after both real peers announce readiness.
        # A wrong expected identity must fail both directions before any CE application exchange starts.
        if bad_pin:
            (gate / 'start-0').touch()
            for process in processes.values():
                assert process.wait(timeout=15) == 2
            for log in logs.values():
                assert 'MESH_CONNECTED' not in log.read_text() and 'MESH_EXCHANGED' not in log.read_text(), log.read_text()
            return {'pairing': name, 'expected_identity_rejection': True}
        # Round zero proves nonpreferred fallback after five seconds; subsequent rounds deliberately race both dials.
        for round_index in range(rounds):
            (gate / f'start-{round_index}').touch()
            texts = observe(processes, logs, f'MESH_EXCHANGED {round_index} ', peaks, thread_limits=thread_limits)
            for role, text in texts.items():
                assert f'MESH_EXCHANGED {round_index} 8' in text.splitlines(), (role, text)
                expected_direction = decisions[role] if round_index else not decisions[role]
                assert f'MESH_CONNECTED {round_index} {int(expected_direction)}' in text.splitlines(), (role, text)
                if round_index:
                    assert f'MESH_DUPLICATE {round_index}' in text.splitlines(), (role, text)
            if telemetry is not None:
                # Hold the authenticated state past one status interval while the peer dispatcher keeps ticking.
                time.sleep(2.1)
            (gate / f'close-{round_index}').touch()
            texts = observe(processes, logs, f'MESH_IDLE {round_index} ', peaks, thread_limits=thread_limits)
            # Exact accepted/closed equality proves complete retirement before another dial on the same engines.
            for role, process in processes.items():
                line = next(line for line in texts[role].splitlines() if line.startswith(f'MESH_IDLE {round_index} '))
                fields = list(map(int, line.split()[1:]))
                index, allocated, incoming, outgoing, closed_incoming, closed_outgoing = fields
                assert index == round_index and incoming == closed_incoming and outgoing == closed_outgoing, line
                assert incoming + outgoing == 1 + 2 * round_index, line
                sample = resources(process.pid)
                sample['allocated_bytes'] = allocated
                sample['thread_baseline'] = thread_limits[role]
                idle[role].append(sample)
            if checkpoint is not None:
                checkpoint(round_index) # Fault injection cannot release a round before both peers retire it.
            if telemetry is not None:
                # Observe idle status before the next round can authenticate another generation.
                time.sleep(2.1)
        budgets = {role: check_growth(samples, warmup, languages[0 if role == 'a' else 1]) for role, samples in idle.items()}
        (gate / 'stop').touch()
        for role, process in processes.items():
            assert process.wait(timeout=5) == 0, logs[role].read_text()
            # Nim reports language-allocator bytes; preserve its original 64-KiB shutdown bound.
            fields = next(line.split() for line in logs[role].read_text().splitlines() if line.startswith('MESH_CLEAN '))
            assert int(fields[2]) <= int(fields[1]) + 65536, fields
        result = {'pairing': name, 'rounds': rounds, 'fallback_timeout_seconds': 5,
                  'bidirectional_queries': rounds * 8, 'duplicate_connections_retired': rounds - 1,
                  'listener_ports': dict(zip(logs, local_ports)), 'retained_engines_per_peer': 2, 'thread_baselines': thread_limits, 'peaks': peaks, 'idle_budgets': budgets,
                  'seconds': time.monotonic() - started}
        (directory / 'resources.json').write_text(json.dumps({'result': result, 'idle_samples': idle}, indent=2) + '\n')
        return result
    finally:
        # Failure paths reap both children before closing their diagnostic streams; no native owner survives the harness.
        for process in processes.values():
            if process.poll() is None:
                process.kill(); process.wait()
        for handle in handles.values():
            handle.close()
