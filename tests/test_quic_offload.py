#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Fixed worker RingVRF verification alongside persistent native QUIC, with bounded owned jobs."""
import hashlib
import json
import os
import re
import socket
import subprocess
import time
from test_quic import ROOT, THREAD_BASELINES
from test_quic_soak import resources, check_growth
import test_bandersnatch as bs

BUILD = ROOT / 'build/offload'


# Pack the independently sourced tiny ticket into fixed copied fields; the worker constructs no implicit domain.
def corpus(directory=None):
    item = json.loads((bs.FIXTURES / 'jam-tiny.json').read_text())
    ticket = item['tickets'][0]
    domain = b'jam_ticket_seal' + bytes.fromhex(item['entropy'][2:]) + bytes([ticket['attempt']])
    wire = (item['capacity'].to_bytes(4, 'little') + bytes.fromhex(item['root'][2:]) +
            bytes.fromhex(ticket['signature'][2:]) + domain + bytes.fromhex(ticket['output'][2:]))
    assert len(domain) == 48 and len(wire) == 1012
    # Isolated compiler runs retain their own trusted fixture without changing any source bytes.
    directory = BUILD if directory is None else directory
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / 'ticket.bin'
    path.write_bytes(wire)
    # Independent keys name the exact cheap/verified/invalid-policy CE lookup fixtures.
    return path, {'fixture_sha256': hashlib.sha256(wire).hexdigest(),
                  'preimage_keys': [hashlib.blake2b(bytes(range(start, start+3)), digest_size=32).hexdigest()
                                    for start in (1, 4, 7)]}


# Keep no-network completion capacity and held shutdown checks identical for direct and cumulative runners.
def selftests(binary, fixture, directory):
    directory.mkdir(parents=True, exist_ok=True)
    results = []
    # These holds belong only to this harness and are never used to claim actual Rust execution.
    for name, flag, gate, markers in (
            ('offload_capacity', '--offload-selftest', '', ('OFFLOAD_SELFTEST 4', 'OFFLOAD_EXHAUSTED', 'OFFLOAD_JOINED 2')),
            ('offload_held_shutdown', '--offload-held-shutdown', str(directory/f'held-{time.time_ns()}'),
             ('OFFLOAD_HELD_SHUTDOWN 4', 'OFFLOAD_STATE 2 2 0 0 0 0 4', 'OFFLOAD_JOINED 2'))):
        path = directory/(name+'.log')
        environment = {**os.environ, 'RAGNAROK_OFFLOAD_FIXTURE': str(fixture),
                       'RAGNAROK_OFFLOAD_REPEATS': '1', 'RAGNAROK_OFFLOAD_GATE': gate}
        with path.open('w') as output:
            process = subprocess.run([str(binary), flag], env=environment, stdout=output,
                                     stderr=subprocess.STDOUT, timeout=30)
        transcript = path.read_text()
        assert process.returncode == 0 and all(marker in transcript.splitlines() for marker in markers), transcript
        results.append(dict(name=name, passed=True, run=dict(exit_code=process.returncode, log=str(path))))
    return results


# One process survives repeated queue pressure, cancellation and proof errors without replacing its listener/workers.
def exercise(language, certificates, fixture, rounds, warmup, repeats, *, binaries=None, directory=None):
    # Use only explicitly selected checked peers; queue pressure, deadlines and finite budgets are unchanged.
    binaries = binaries or {name: BUILD / f'{name}-peer' for name in THREAD_BASELINES}
    fixed_threads = THREAD_BASELINES[language] + 2
    directory = BUILD / language if directory is None else directory
    directory.mkdir(parents=True, exist_ok=True)
    gate = directory / f'release-{time.time_ns()}'
    stop = directory / f'stop-{time.time_ns()}'
    cancel = directory / f'cancel-{time.time_ns()}'
    log = directory / 'server.log'
    children, handles, idle, peaks = [], [], [], {}
    accepted = 0
    # Reserve an IPv6 loopback port; READY confirms that the service really owns the released port.
    with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as reservation:
        reservation.bind(('::1', 0))
        port = reservation.getsockname()[1]
    environment = {**os.environ, 'RAGNAROK_SERVICE_STOP': str(stop), 'RAGNAROK_OFFLOAD_GATE': str(gate),
                   'RAGNAROK_OFFLOAD_FIXTURE': str(fixture), 'RAGNAROK_OFFLOAD_REPEATS': str(repeats), 'RAGNAROK_OFFLOAD_CANCEL': str(cancel)}
    output = log.open('w'); handles.append(output)
    server = subprocess.Popen([str(binaries[language]), 'server', str(port),
        str(certificates / 'a.cert.pem'), str(certificates / 'a.key.pem'), '-', 'jamnp-s/1/00000000',
        '300000', 'offload'], env=environment, stdout=output, stderr=subprocess.STDOUT)
    children.append(server)

    # Check fixed worker/resource ceilings throughout every lifecycle wait, not just at idle.
    def watch(predicate, seconds=20):
        deadline = time.monotonic() + seconds
        while True:
            text = log.read_text()
            assert server.poll() is None, (language, server.returncode, text[-4000:])
            sample = resources(server.pid)
            assert 1 <= sample['threads'] <= fixed_threads and sample['rss_bytes'] < 256 * 1024 * 1024, (language, sample)
            if 'READY' in text.splitlines():
                assert sample['threads'] == fixed_threads, (language, sample) # Startup may be observed before the fixed workers exist.
            for metric, value in sample.items():
                peaks[metric] = max(peaks.get(metric, 0), value)
            if predicate(text):
                return text
            assert time.monotonic() < deadline, (language, text[-5000:], 'offload observation deadline')
            time.sleep(0.02)

    # Generations are monotonic pool IDs; use the newest state so an earlier wave cannot satisfy a new barrier.
    def state(text):
        lines = re.findall(r'^OFFLOAD_STATE ([0-9 ]+)$', text, re.M)
        return tuple(map(int, lines[-1].split())) if lines else (0,)*7

    # Each external client uses one exact query, allowing rejection/cancellation to be checked independently.
    def launch(implementation, mode):
        nonlocal accepted
        accepted += 1
        # Cycle native clients without changing queue generations, capacity or cancellation counts.
        path = directory / f'{accepted}-{implementation}-{mode}.log'
        handle = path.open('w'); handles.append(handle)
        process = subprocess.Popen([str(binaries[implementation]), 'client', str(port),
            str(certificates / 'b.cert.pem'), str(certificates / 'b.key.pem'), str(certificates / 'a.pub'),
            'jamnp-s/1/00000000', '20000', mode], env=environment, stdout=handle, stderr=subprocess.STDOUT)
        children.append(process)
        return process, path

    # Authentication is insufficient: success must include exactly one validated reply and FIN.
    def settle(client, successful):
        process, path = client
        code = process.wait(timeout=25)
        text = path.read_text()
        assert code == (0 if successful else 2), (path.name, code, text)
        assert ('EXCHANGE_OK 1' in text.splitlines()) == successful, (path.name, text)

    started = time.monotonic()
    try:
        watch(lambda text: 'READY' in text.splitlines())
        for wave in range(rounds):
            # Preserve the complete fifteen-client wave with distinct connections to the Nim listener.
            if gate.exists():
                gate.unlink() # Re-arm only this harness's test hold while there are no retained jobs.
            base = wave * 7
            first = launch('nim', 'proof')
            watch(lambda text: state(text)[1] == 1 and state(text)[6] == 1)
            second = launch('nim', 'proof')
            watch(lambda text: state(text)[1] == 2 and state(text)[6] == 2)
            third = launch('nim', 'proof')
            watch(lambda text: state(text)[0] == 1 and state(text)[6] == 3)
            fourth = launch('nim', 'proof')
            watch(lambda text: state(text)[:2] == (2, 2) and state(text)[6] == 4)
            overflow = launch('nim', 'proof')
            settle(overflow, False)
            # Cheap networking continues even when both workers and all admission slots are held.
            for implementation in ('nim', 'nim'):
                settle(launch(implementation, 'light'), True)
            fourth[0].kill(); assert fourth[0].wait(timeout=5) == -9 # Queued input has no active FFI borrower.
            first[0].kill(); assert first[0].wait(timeout=5) == -9 # Running ownership remains retained until completion.
            watch(lambda text: f'OFFLOAD_CANCEL {base+4} 1' in text.splitlines() and
                  f'OFFLOAD_CANCEL {base+1} 2' in text.splitlines() and state(text)[3] == 1 and state(text)[6] == 3)
            replacement = launch('nim', 'proof')
            watch(lambda text: state(text)[:2] == (2, 2) and state(text)[6] == 4)
            gate.touch() # The workers now run real Rust verification, including the cancelled running job.
            watch(lambda text: state(text)[4] == 2)
            before = log.read_text().count('OFFLOAD_LIGHT_DONE ')
            for implementation in ('nim', 'nim', 'nim', 'nim'):
                settle(launch(implementation, 'light'), True)
            progress = re.findall(r'^OFFLOAD_LIGHT_DONE (\d+)$', log.read_text(), re.M)[before:]
            assert any(int(n) > 0 for n in progress), (language, wave, 'no networking during actual crypto', progress)
            for client in (second, third, replacement):
                settle(client, True)
            watch(lambda text: state(text)[6] == 0 and state(text)[5] == wave*2+1)
            invalid = launch('nim', 'invalid-proof')
            settle(invalid, False)
            settle(launch('nim', 'light'), True)
            if cancel.exists():
                cancel.unlink() # Re-arm this controller's actual-FFI cancellation only after prior jobs retire.
            active_cancel = launch('nim', 'proof-cancel')
            watch(lambda text: state(text)[4] == 1 and state(text)[6] == 1)
            cancel.touch() # This native client sends reset/connection close while real Rust verification is active.
            settle(active_cancel, False)
            watch(lambda text: f'OFFLOAD_CANCEL {base+7} 2' in text.splitlines() and
                  state(text)[3] == 1 and state(text)[4] == 1 and state(text)[6] == 1)
            watch(lambda text: state(text)[6] == 0 and state(text)[5] == (wave+1)*2)
            text = watch(lambda text: state(text)[6] == 0 and
                         any(line.startswith(f'SERVICE_IDLE {accepted} {accepted} ') for line in text.splitlines()))
            assert text.count('OFFLOAD_REJECT Capacity\n') == wave+1, text[-3000:]
            assert text.count('OFFLOAD_REJECT Proof\n') == wave+1, text[-3000:]
            assert text.count('OFFLOAD_VERIFIED ') == (wave+1)*3, text[-3000:]
            assert 'OFFLOAD_STALE ' not in text, 'Cancelled/reused owners received a stale completion'
            sample = resources(server.pid)
            fields = next(line.split() for line in reversed(text.splitlines()) if line.startswith('SERVICE_IDLE '))
            sample['allocated_bytes'] = int(fields[3])
            sample['thread_baseline'] = fixed_threads
            idle.append(sample)
            print(f'{language} offload: {wave+1}/{rounds} waves; queue cap 4, workers 2, actual-crypto networking passed', flush=True)
        # Apply the same scoped heap, RSS, descriptor and fixed-worker checks as the other retained profiles.
        growth = check_growth(idle, warmup, language)
        assert all(x['threads'] == fixed_threads for x in idle), idle
        # Exit with two actual crypto batches running and two queued jobs. Join waits for Rust before releasing owners.
        gate.unlink()
        pending = [launch('nim', 'proof') for index in range(4)]
        watch(lambda text: state(text)[:2] == (2, 2) and state(text)[6] == 4)
        gate.touch()
        watch(lambda text: state(text)[4] == 2 and state(text)[6] == 4)
        stop.touch()
        assert server.wait(timeout=25) == 0, log.read_text()[-5000:]
        final = log.read_text()
        assert 'OFFLOAD_SHUTDOWN_PENDING 4' in final.splitlines() and 'OFFLOAD_JOINED 2' in final.splitlines(), final[-3000:]
        # Complete cleanup is measured after transport destruction and worker join, rather than hidden by process exit.
        values = re.findall(r'^SERVICE_CLEAN (\d+) (\d+)$', final, re.M)
        assert len(values) == 1 and int(values[0][1]) <= int(values[0][0])+65536, values
        return {'language': language, 'rounds': rounds, 'runtime_thread_baseline': THREAD_BASELINES[language], 'workers': 2, 'job_cap': 4,
                'verification_repeats_per_job': repeats, 'verified_jobs': rounds*3,
                'wrong_domain_rejections': rounds, 'capacity_rejections': rounds,
                'queued_cancellations': rounds, 'held_running_cancellations': rounds, 'actual_crypto_cancellations': rounds,
                'shutdown_pending_jobs': 4, 'healthy_light_queries': rounds*7,
                'elapsed_seconds': time.monotonic()-started, 'idle': idle, 'peaks': peaks, 'growth': growth}
    finally:
        (directory / 'resources.json').write_text(json.dumps({'idle': idle, 'peaks': peaks}, indent=2)+'\n')
        # Any failed assertion retires only harness-owned processes and closes all diagnostic handles.
        for process in children:
            if process.poll() is None:
                process.kill()
            process.wait()
        for handle in handles:
            handle.close()
