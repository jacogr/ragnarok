#!/usr/bin/env python3
"""Bounded IPv6 peer-loss recovery and connection/stream saturation; no throughput assertions."""
from mojo_support import networking_candidates
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from test_quic import BUILD, build_peers, dependencies, fixtures, THREAD_BASELINES
from test_quic_mesh import ports
from test_quic_soak import resources, check_growth


# Wait for exact lifecycle observations on currently live processes, retaining bounded resource peaks.
def watch(processes, logs, predicates, peaks, seconds=15):
    deadline = time.monotonic() + seconds
    # A crashed process or stale transcript cannot satisfy a later recovery/admission barrier.
    while True:
        texts = {role: path.read_text() for role, path in logs.items()}
        for role, process in processes.items():
            assert process.poll() is None, (role, process.returncode, texts[role][-4000:])
            sample = resources(process.pid)
            language = Path(process.args[0]).name.split('-')[0]
            expected_threads = THREAD_BASELINES[language]
            assert 1 <= sample['threads'] <= expected_threads and sample['rss_bytes'] < 256 * 1024 * 1024, (role, sample, expected_threads, texts[role][-4000:])
            # SDK workers may still be starting before the first native readiness/authentication marker.
            if any(line == 'READY' or line == 'AUTH_OK' or line.startswith('MESH_READY ') for line in texts[role].splitlines()):
                assert sample['threads'] == expected_threads, ('changed fixed runtime thread count', sample, expected_threads)
            for metric, value in sample.items():
                peaks[role][metric] = max(peaks[role].get(metric, 0), value)
        if all(predicate(texts[role]) for role, predicate in predicates.items()):
            return texts
        assert time.monotonic() < deadline, (texts, 'observation deadline')
        time.sleep(0.02)


# Remove only harness-owned children on a failed assertion, and close the diagnostic files after reaping them.
def retire(processes, handles):
    for process in processes:
        if process.poll() is None:
            process.kill(); process.wait()
    for handle in handles:
        handle.close()


# Check final application/I/O cleanup after graceful controller shutdown, excluding deliberately killed victims.
def clean(language, text):
    if language == 'odin':
        assert 'MESH_CLEAN 0 0' in text.splitlines(), text
    else:
        fields = next(line.split() for line in text.splitlines() if line.startswith('MESH_CLEAN '))
        assert int(fields[2]) <= int(fields[1]) + 65536, fields


# One stable logical peer survives twelve peer deaths and successfully exchanges queries after each restart.
def disruption(languages, folder, rounds, warmup):
    name = '-'.join(languages)
    directory = BUILD / 'resilience' / f'disruption-{name}'
    directory.mkdir(parents=True, exist_ok=True)
    keeper_gate = directory / f'keeper-gate-{time.time_ns()}'
    keeper_gate.mkdir()
    keeper_log = directory / 'keeper.log'
    local_ports = ports()
    children, handles, idle = [], [], []
    peaks = {'keeper': {}, 'victim': {}}

    # Both processes use the same pinned TLS/CE policy; only their explicitly selected expiry profile differs.
    def launch(role, language, gate, count, path):
        index = 0 if role == 'a' else 1
        other = 'b' if role == 'a' else 'a'
        command = [str(BUILD / f'{language}-peer'), 'mesh', str(local_ports[index]), str(local_ports[1-index]),
                   str(folder / f'{role}.cert.pem'), str(folder / f'{role}.key.pem'), str(folder / f'{role}.pub'),
                   str(folder / f'{other}.pub'), 'jamnp-s/1/00000000', str(gate)]
        output = path.open('w'); handles.append(output)
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
            env={**os.environ, 'RAGNAROK_MESH_ROUNDS': str(count), 'RAGNAROK_MESH_FALLBACK': '0',
                 'RAGNAROK_MESH_DISRUPT': '1'})
        children.append(process)
        return process

    keeper = launch('a', languages[0], keeper_gate, rounds + 1, keeper_log)
    started = time.monotonic()
    try:
        watch({'keeper': keeper}, {'keeper': keeper_log}, {'keeper': lambda text: 'MESH_READY ' in text}, peaks)
        # The counterpart restarts with the same certificate/identity/listener port; the keeper's two engines never restart.
        for index in range(rounds):
            victim_gate = directory / f'victim-{index}-{time.time_ns()}'
            victim_gate.mkdir()
            victim_log = directory / f'victim-{index}.log'
            victim = launch('b', languages[1], victim_gate, 1, victim_log)
            processes = {'keeper': keeper, 'victim': victim}
            logs = {'keeper': keeper_log, 'victim': victim_log}
            watch(processes, logs, {'victim': lambda text: 'MESH_READY ' in text}, peaks)
            (keeper_gate / f'start-{index}').touch(); (victim_gate / 'start-0').touch()
            # Separate healthy completion from pending work so an early peer cannot prevent the other's idle-stream barrier.
            watch(processes, logs, {
                'keeper': lambda text: f'MESH_EXCHANGED {index} 8' in text.splitlines(),
                'victim': lambda text: 'MESH_EXCHANGED 0 8' in text.splitlines()}, peaks)
            (keeper_gate / f'pending-{index}').touch(); (victim_gate / 'pending-0').touch()
            texts = watch(processes, logs, {
                'keeper': lambda text: f'MESH_PENDING {index} 8' in text.splitlines(),
                'victim': lambda text: 'MESH_PENDING 0 8' in text.splitlines()}, peaks)
            assert f'MESH_EXCHANGED {index} 8' in texts['keeper'].splitlines()
            assert 'MESH_EXCHANGED 0 8' in texts['victim'].splitlines()
            victim.kill(); assert victim.wait(timeout=5) == -9
            lost_at = time.monotonic()
            (keeper_gate / f'close-{index}').touch()
            texts = watch({'keeper': keeper}, {'keeper': keeper_log}, {
                'keeper': lambda text: any(line.startswith(f'MESH_IDLE {index} ') for line in text.splitlines())}, peaks)
            assert f'MESH_RECOVERED {index} 8' in texts['keeper'].splitlines()
            line = next(line for line in texts['keeper'].splitlines() if line.startswith(f'MESH_IDLE {index} '))
            _, allocated, incoming, outgoing, closed_incoming, closed_outgoing = map(int, line.split()[1:])
            assert incoming == outgoing == closed_incoming == closed_outgoing == index + 1, line
            sample = resources(keeper.pid)
            sample.update(thread_baseline=THREAD_BASELINES[languages[0]], allocated_bytes=allocated, recovery_seconds=time.monotonic() - lost_at)
            assert sample['recovery_seconds'] < 10, sample
            idle.append(sample)
        # Every forced loss, including the final one, must be followed by healthy work on these same retained engines.
        final_gate = directory / f'final-{time.time_ns()}'
        final_gate.mkdir()
        (keeper_gate / 'healthy-final').touch(); (final_gate / 'healthy-final').touch()
        final_log = directory / 'victim-final.log'
        final_peer = launch('b', languages[1], final_gate, 1, final_log)
        processes = {'keeper': keeper, 'victim': final_peer}
        logs = {'keeper': keeper_log, 'victim': final_log}
        watch(processes, logs, {'victim': lambda text: 'MESH_READY ' in text}, peaks)
        (keeper_gate / f'start-{rounds}').touch(); (final_gate / 'start-0').touch()
        watch(processes, logs, {
            'keeper': lambda text: f'MESH_EXCHANGED {rounds} 8' in text.splitlines(),
            'victim': lambda text: 'MESH_EXCHANGED 0 8' in text.splitlines()}, peaks)
        (keeper_gate / f'close-{rounds}').touch(); (final_gate / 'close-0').touch()
        watch(processes, logs, {
            'keeper': lambda text: any(line.startswith(f'MESH_IDLE {rounds} ') for line in text.splitlines()),
            'victim': lambda text: any(line.startswith('MESH_IDLE 0 ') for line in text.splitlines())}, peaks)
        (final_gate / 'stop').touch()
        assert final_peer.wait(timeout=5) == 0, final_log.read_text()
        clean(languages[1], final_log.read_text())
        budgets = check_growth(idle, warmup)
        (keeper_gate / 'stop').touch()
        assert keeper.wait(timeout=5) == 0, keeper_log.read_text()
        clean(languages[0], keeper_log.read_text())
        result = {'pairing': name, 'peer_losses': rounds, 'pending_operations_settled': rounds * 8,
                  'restarts': rounds, 'healthy_queries': (rounds + 1) * 8, 'peaks': peaks, 'idle_budgets': budgets,
                  'max_recovery_seconds': max(sample['recovery_seconds'] for sample in idle),
                  'seconds': time.monotonic() - started}
        (directory / 'resources.json').write_text(json.dumps({'result': result, 'idle_samples': idle}, indent=2) + '\n')
        return result
    finally:
        retire(children, handles)


# Parse bounded native service state without depending on adjacency to unrelated OS/library diagnostics.
def states(text):
    return [tuple(map(int, line.split()[1:])) for line in text.splitlines() if line.startswith('LOAD_STATE ')]


# Reproduce connection loss after authentication but before any stream callback can report failure.
def closed_before_request(languages, folder):
    directory = BUILD / 'resilience' / f'closed-before-request-{"-".join(languages)}'
    directory.mkdir(parents=True, exist_ok=True)
    port = ports()[0]
    logs = {role: directory / f'{role}.log' for role in ('server', 'client')}
    processes, handles = {}, []
    peaks = {role: {} for role in logs}
    try:
        # The listener uses the existing two-second crash profile; no new protocol/settings are introduced.
        output = logs['server'].open('w'); handles.append(output)
        processes['server'] = subprocess.Popen([str(BUILD / f'{languages[0]}-peer'), 'server', str(port),
            str(folder / 'a.cert.pem'), str(folder / 'a.key.pem'), '-', 'jamnp-s/1/00000000', '60000', 'overload'],
            env={**os.environ, 'RAGNAROK_SERVICE_STOP': str(directory / f'stop-{time.time_ns()}')},
            stdout=output, stderr=subprocess.STDOUT)
        watch({'server': processes['server']}, {'server': logs['server']},
              {'server': lambda text: 'READY' in text.splitlines()}, {'server': peaks['server']})
        output = logs['client'].open('w'); handles.append(output)
        processes['client'] = subprocess.Popen([str(BUILD / f'{languages[1]}-peer'), 'client', str(port),
            str(folder / 'b.cert.pem'), str(folder / 'b.key.pem'), str(folder / 'a.pub'),
            'jamnp-s/1/00000000', '60000', 'idle'], stdout=output, stderr=subprocess.STDOUT)
        # Idle mode deliberately opens no streams, so only connection retirement can settle this failure.
        watch(processes, logs, {'client': lambda text: 'AUTH_OK' in text.splitlines()}, peaks)
        processes['server'].kill(); assert processes['server'].wait(timeout=5) == -9
        started = time.monotonic()
        assert processes['client'].wait(timeout=5) == 2, logs['client'].read_text()
        text = logs['client'].read_text()
        assert 'AUTH_OK' in text.splitlines() and 'CONNECTION_CLOSED' in text.splitlines(), text
        assert 'EXCHANGE_OK' not in text, text # Retained handshake history cannot fabricate application success.
        return {'server': languages[0], 'client': languages[1], 'application_streams': 0,
                'closed_seconds': time.monotonic() - started, 'peaks': peaks}
    finally:
        retire(list(processes.values()), handles) # Reap only this regression's peers after success or failure.


# Keep the five-second probe gate strict while attaching native diagnostics to any future missed retirement.
def settle_probe(process, path, expected):
    try:
        code = process.wait(timeout=5)
    except subprocess.TimeoutExpired as error:
        # TimeoutExpired alone omits the client's lifecycle transcript, obscuring authenticated-close races.
        raise AssertionError(f'{path.name}: probe did not retire within five seconds\n{path.read_text()[-4000:]}') from error
    assert code == expected, (path.name, code, path.read_text())


# A retained IPv6 listener must refuse excess admission, release interrupted slots and resume healthy CE work.
def overload(language, folder, rounds, warmup):
    directory = BUILD / 'resilience' / f'overload-{language}'
    directory.mkdir(parents=True, exist_ok=True)
    stop = directory / f'stop-{time.time_ns()}'
    server_log = directory / 'server.log'
    port = ports()[0]
    handles, children, idle = [], [], []
    peaks = {'server': {}}
    output = server_log.open('w'); handles.append(output)
    server = subprocess.Popen([str(BUILD / f'{language}-peer'), 'server', str(port), str(folder / 'a.cert.pem'),
        str(folder / 'a.key.pem'), '-', 'jamnp-s/1/00000000', '120000', 'overload'],
        env={**os.environ, 'RAGNAROK_SERVICE_STOP': str(stop)}, stdout=output, stderr=subprocess.STDOUT)
    children.append(server)
    started = time.monotonic()

    # Each load source uses native nonblocking UDP/TLS; mixed implementations share only public fixture identity bytes.
    def client(index, label, implementation, mode):
        path = directory / f'{index}-{label}.log'
        output = path.open('w'); handles.append(output)
        process = subprocess.Popen([str(BUILD / f'{implementation}-peer'), 'client', str(port), str(folder / 'b.cert.pem'),
            str(folder / 'b.key.pem'), str(folder / 'a.pub'), 'jamnp-s/1/00000000', '60000', mode],
            stdout=output, stderr=subprocess.STDOUT)
        children.append(process)
        return process, path

    # Only the retained server is the resource subject here; intentionally killed load sources are reaped separately.
    def server_state(predicate):
        return watch({'server': server}, {'server': server_log}, {'server': predicate}, peaks)['server']

    accepted, connection_rejects, stream_rejects = 0, 0, 0
    try:
        server_state(lambda text: 'READY' in text.splitlines())
        # Repeat admission/recovery waves in the same listener PID, without rebuilding its TLS, socket or engine.
        for index in range(rounds):
            base_idle = server_log.read_text().count('SERVICE_IDLE ')
            idle_clients = [client(index, f'idle-{i}', 'nim' if i % 2 == 0 else 'odin', 'idle') for i in range(16)]
            server_state(lambda text: bool(states(text)) and states(text)[-1][0] == 16)
            excess, excess_log = client(index, 'excess-connection', 'odin' if language == 'nim' else 'nim', 'probe')
            connection_rejects += 1
            server_state(lambda text: any(state[2] >= connection_rejects for state in states(text)))
            settle_probe(excess, excess_log, 2)
            # All sixteen accepted connections must remain intact while the seventeenth is refused.
            assert all(process.poll() is None for process, _ in idle_clients)
            for process, _ in idle_clients:
                process.kill(); process.wait()
            accepted += 16
            server_state(lambda text: text.count('SERVICE_IDLE ') > base_idle)
            # Eight holders each send eight correct query prefixes without FIN, occupying exactly 64 native slots.
            holders = [client(index, f'holder-{i}', 'nim' if i % 2 == 0 else 'odin', 'holder') for i in range(8)]
            server_state(lambda text: bool(states(text)) and states(text)[-1][1] == 64)
            rejected, rejected_log = client(index, 'excess-stream', 'odin' if language == 'nim' else 'nim', 'probe')
            stream_rejects += 1
            server_state(lambda text: any(state[3] >= stream_rejects for state in states(text)))
            settle_probe(rejected, rejected_log, 2)
            # Release one connection's eight pending owners while seven loaded connections remain active.
            holders[0][0].kill(); holders[0][0].wait()
            server_state(lambda text: bool(states(text)) and states(text)[-1][1] == 56)
            healthy, healthy_log = client(index, 'healthy-after-release', 'nim' if language == 'odin' else 'odin', 'probe')
            settle_probe(healthy, healthy_log, 0)
            assert 'EXCHANGE_OK 1' in healthy_log.read_text().splitlines(), healthy_log.read_text()
            assert all(process.poll() is None for process, _ in holders[1:]), 'loaded peers were displaced by healthy work'
            for process, _ in holders[1:]:
                process.kill(); process.wait()
            accepted += 10 # Eight holders plus the rejected-stream probe and the subsequent successful probe.
            text = server_state(lambda text: any(line.startswith(f'SERVICE_IDLE {accepted} {accepted} ') for line in text.splitlines()))
            line = next(line for line in text.splitlines() if line.startswith(f'SERVICE_IDLE {accepted} {accepted} '))
            allocated = int(line.split()[3])
            sample = resources(server.pid); sample['allocated_bytes'] = allocated
            sample['thread_baseline'] = THREAD_BASELINES[language]
            idle.append(sample)
            assert max(state[1] for state in states(text)) == 64 and max(state[4] for state in states(text)) == 64
            assert max(state[2] for state in states(text)) == connection_rejects, text[-2000:]
            assert max(state[3] for state in states(text)) == stream_rejects, text[-2000:]
        budgets = check_growth(idle, warmup)
        stop.touch()
        assert server.wait(timeout=5) == 0, server_log.read_text()
        text = server_log.read_text()
        assert f'SERVICE_DONE {accepted} {accepted} 16' in text.splitlines(), text
        if language == 'odin':
            assert 'SERVICE_CLEAN 0 0' in text.splitlines(), text
        result = {'language': language, 'waves': rounds, 'connection_ceiling': 16, 'stream_ceiling': 64,
                  'connection_capacity_rejections': connection_rejects, 'stream_capacity_rejections': stream_rejects,
                  'healthy_queries_after_release': rounds, 'retired_connections': accepted,
                  'peaks': peaks, 'idle_budgets': budgets, 'seconds': time.monotonic() - started}
        (directory / 'resources.json').write_text(json.dumps({'result': result, 'idle_samples': idle}, indent=2) + '\n')
        return result
    finally:
        retire(children, handles)


# Run the two experiments sequentially because their deliberately shared fixture directory must stay immutable in flight.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--fetch', action='store_true')
    parser.add_argument('--rounds', type=int, default=12)
    parser.add_argument('--warmup', type=int, default=4)
    parser.add_argument('--mojo', action='store_true', help='include the pinned native Mojo candidate')
    args = parser.parse_args()
    assert 12 <= args.rounds <= 16 and 0 <= args.warmup <= args.rounds - 8
    output = BUILD / 'resilience/results.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    report = {'complete': False, 'closed_before_request': [], 'disruption': [], 'overload': []}
    output.write_text(json.dumps(report) + '\n')
    if not args.skip_build:
        build_peers(dependencies(args.fetch))
    candidates = networking_candidates(BUILD, args.mojo, args.skip_build, THREAD_BASELINES)
    folder = fixtures(BUILD / 'resilience/fixtures') # Keep retained TLS identities private to this harness.
    try:
        for languages in [(a, b) for a in candidates for b in candidates]:
            report['closed_before_request'].append(closed_before_request(languages, folder))
            output.write_text(json.dumps(report, indent=2) + '\n')
            print('PASS close before request', '-'.join(languages), flush=True)
        for languages in [(a, b) for a in candidates for b in candidates]:
            report['disruption'].append(disruption(languages, folder, args.rounds, args.warmup))
            output.write_text(json.dumps(report, indent=2) + '\n')
            print('PASS disruption', '-'.join(languages), args.rounds, 'peer deaths with pending work', flush=True)
        for language in candidates:
            report['overload'].append(overload(language, folder, args.rounds, args.warmup))
            output.write_text(json.dumps(report, indent=2) + '\n')
            print('PASS overload', language, args.rounds, 'admission/recovery waves', flush=True)
    except Exception as error:
        report['failure'] = str(error)
        output.write_text(json.dumps(report, indent=2) + '\n')
        raise
    report['complete'] = True
    output.write_text(json.dumps(report, indent=2) + '\n')


# Importing resource/lifecycle helpers starts no peer and alters no networking state.
if __name__ == '__main__':
    main()
