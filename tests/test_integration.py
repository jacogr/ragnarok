#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Shared fixtures and process checks for owned C.2 codecs, Blake2b-256 and persistent CE 143.

Exposes corpus, service, rounds_total for the verification harness.
"""
from functools import partial
import hashlib
import json
import os
import re
import socket
import subprocess
from test_quic import application_binaries, ROOT, THREAD_BASELINES
from test_codec import reference_encode
from digest_checks import wire_for
from test_quic_service import wait_service
from test_quic_soak import resources, check_growth

BUILD = ROOT / 'build/integration'


# Treat official binaries as immutable; compare their JSON against the independent mathematical codec oracle.
def corpus():
    directory = BUILD / 'wires'
    directory.mkdir(exist_ok=True)
    official = []
    for chain, name in (('tiny', 'work_result_0'), ('tiny', 'work_result_1'),
                        ('full', 'work_result_0'), ('full', 'work_result_1')):
        folder = ROOT / 'vendor/jamtestvectors/codec' / chain
        item = json.loads((folder / f'{name}.json').read_text())
        tag, blob = (0, bytes.fromhex(item['result']['ok'][2:])) if 'ok' in item['result'] else (2, b'')
        value = (item['service_id'], bytes.fromhex(item['code_hash'][2:]), bytes.fromhex(item['payload_hash'][2:]),
                 item['accumulate_gas'], tag, blob, [item['refine_load'][key] for key in
                 ('gas_used', 'imports', 'extrinsic_count', 'extrinsic_size', 'exports')])
        wire = (folder / f'{name}.bin').read_bytes()
        assert wire_for(value, reference_encode) == wire, (chain, name)
        official.append(wire)
    big = wire_for((6, bytes(range(32)), bytes(range(32, 64)), 42, 0,
                    bytes(i % 251 for i in range(1024 * 1024)), [1, 128, 16384, 2**56, 2**64 - 1]), reference_encode)
    last = wire_for((7, bytes(32), bytes([7]) * 32, 2**64 - 1, 0, b'owned-after-failure',
                    [2**64 - 1, 0, 1, 127, 128]), reference_encode)
    # Tiny/full published digests coincide; authored service-ID variants distinguish the two fault scenarios.
    wires = [official[0], official[1], official[0][:-1], official[0] + b'\0',
             (4).to_bytes(4, 'little') + official[2][4:],
             (5).to_bytes(4, 'little') + official[3][4:], big, last]
    # Exact hashes name all public fixtures, including the intentionally malformed/trailing records.
    hashes = [hashlib.blake2b(wire, digest_size=32).hexdigest() for wire in wires]
    assert len(set(hashes)) == 8, 'Fixture lookup keys must be unambiguous'
    for index, wire in enumerate(wires):
        (directory / f'{index}.bin').write_bytes(wire)
    return directory, hashes


# One persistent listener processes simultaneous independent clients through every composed failure/lifetime path.
def service(language, certificates, wires, rounds, warmup, *, binaries=None, directory=None):
    # Trial binaries reuse the exact fixture/stream workload and keep their outputs isolated.
    binaries = application_binaries(binaries)
    observe = partial(wait_service, thread_limit=THREAD_BASELINES[language])
    directory = BUILD / language if directory is None else directory
    directory.mkdir(parents=True, exist_ok=True)
    stop = directory / 'stop'
    if stop.exists():
        stop.unlink() # Retire only this harness's previous stop control before the new listener starts.
    environment = {**os.environ, 'RAGNAROK_SERVICE_STOP': str(stop), 'RAGNAROK_INTEGRATION_FIXTURES': str(wires)}
    log = directory / 'server.log'
    handles, children, idle, peaks = [], [], [], {}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    server_output = log.open('w')
    server = subprocess.Popen([str(binaries[language]), 'server', str(port),
                               str(certificates / 'a.cert.pem'), str(certificates / 'a.key.pem'), '-',
                               'jamnp-s/1/00000000', '120000', 'integration'], env=environment,
                              stdout=server_output, stderr=subprocess.STDOUT)
    try:
        observe(server, log, lambda text: 'READY\n' in text, peaks)
        for iteration in range(rounds):
            active = []
            # Three concurrent identities retain the same multi-peer workload using the Nim implementation.
            for index, (client_language, identity) in enumerate((('nim', 'b'), ('nim', 'c'), ('nim', 'd'))):
                path = directory / f'{iteration}-{index}.client.log'
                output = path.open('w')
                handles.append(output)
                process = subprocess.Popen([str(binaries[client_language]), 'client', str(port),
                                            str(certificates / f'{identity}.cert.pem'), str(certificates / f'{identity}.key.pem'),
                                            str(certificates / 'a.pub'), 'jamnp-s/1/00000000', '5000', 'integrated'],
                                           env=environment, stdout=output, stderr=subprocess.STDOUT)
                children.append(process)
                active.append((process, path, client_language))
            # Exact healthy/rejection/cancellation counts are checked by both the native CLI and the independent harness.
            for process, path, implementation in active:
                assert process.wait(timeout=10) == 0, (path.name, path.read_text())
                text = path.read_text()
                assert text.count('EXCHANGE_OK 8\n') == 1, text
                assert text.count('HEALTHY_OK\n') == 3 and text.count('EXPECTED_REJECT\n') == 4 and text.count('CANCEL_OK\n') == 1, text
                reason = 'HashMismatch'
                assert text.count(f'INTEGRATION_REJECT {reason}\n') == 1, text
                assert text.count('OWNED_VERIFIED\n') == 3, text
            total = 3 * (iteration + 1)
            text = observe(server, log, lambda text: f'SERVICE_IDLE {total} {total} ' in text, peaks)
            match = re.findall(rf'^SERVICE_IDLE {total} {total} (\d+)(?: (\d+))?$', text, re.M)
            assert len(match) == 1, text[-2000:]
            sample = resources(server.pid)
            sample['thread_baseline'] = THREAD_BASELINES[language]
            sample['allocated_bytes'] = int(match[0][0])
            idle.append(sample)
            print(f'{language} integration: {iteration + 1}/{rounds} waves', flush=True)
        text = log.read_text()
        count = rounds * 3
        # Every server-side late failure releases its temporary owner; cancellation releases a successfully captured owner.
        for reason in ('Codec', 'Trailing', 'Lookup'):
            assert text.count(f'INTEGRATION_REJECT {reason}\n') == count, (reason, text[-2000:])
        assert text.count('OWNED_VERIFIED\n') == count * 5, text[-2000:]
        assert text.count('OWNED_CANCEL_RELEASE\n') == count, text[-2000:]
        assert text.count('BACKPRESSURE\n') >= count, text[-2000:]
        growth = check_growth(idle, warmup, language)
        stop.touch() # Only fully retired connections/stream slots permit normal listener shutdown.
        assert server.wait(timeout=5) == 0, log.read_text()[-2000:]
        final = log.read_text()
        assert f'SERVICE_DONE {count} {count} 3\n' in final, final[-2000:]
        clean = re.findall(r'^SERVICE_CLEAN (\d+) (\d+)$', final, re.M)
        assert len(clean) == 1 and int(clean[0][1]) <= int(clean[0][0]) + 65536, clean
        return {'language': language, 'connections': count, 'peak_connections': 3, 'peaks': peaks,
                'idle': idle, 'growth': growth, 'cancelled_snapshot_releases': count}
    finally:
        (directory / 'resources.json').write_text(json.dumps({'peaks': peaks, 'idle': idle}, indent=2) + '\n')
        for process in [server, *children]:
            if process.poll() is None:
                process.kill() # A harness assertion cannot leave borrowed callback owners running indefinitely.
            process.wait()
        for handle in [server_output, *handles]:
            handle.close()


# Shared arithmetic keeps the reported workload equal to one listener, three clients and eight streams per wave.
def rounds_total(rounds):
    return rounds * 2 * 3 * 8
