# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Real JAM Tart incoming handshake replay and listener generation reuse after a collector restart.

Exposes verify_incoming and run_incoming for collector-observed incoming replay and listener
reuse.
"""
from contextlib import ExitStack
import json
import os
import time

from test_telemetry_interop import ROOT, VARIANTS, ports, receive, stop
from telemetry_interop_restart import RegistrationRelay, RestartSession, verify_registrations


# Validate every captured field and count status frames in the original per-node position namespace.
def verify_incoming(before, after, server_identity, clients, relay_ports, rejected):
    assert before and all(row['node_id'] == server_identity for row in before)
    starts = [index for index, row in enumerate(before) if row['event_type'] == 21]
    assert len(starts) == 1 and all(row['event_type'] in (10, 21) for row in before)
    original = starts[0]
    assert after and after[0]['node_id'] == server_identity and after[0]['event_type'] == 0
    assert list(after[0]['event']) == ['Dropped']
    skipped = after[0]['event']['Dropped']
    prefix = skipped['num']
    assert isinstance(prefix, int) and len(before) <= prefix < 64
    assert 0 < skipped['timestamp'] <= skipped['last_timestamp']
    expected = [22, 21, 23, 27] if rejected else [23, 27, 21, 23, 27]
    lifecycle = [row['event_type'] for row in after[1:] if row['event_type'] != 10]
    assert lifecycle == expected, lifecycle
    attempts, generation = [original], 0
    for rows, base, recovered in ((before, 0, False), (after[1:], prefix, True)):
        # A dropped prefix advances by its count; it is not itself a position in the new stream.
        for offset, row in enumerate(rows):
            assert row['node_id'] == server_identity
            tag = row['event_type']
            assert tag in (10, 21, 22, 23, 27) and list(row['event']) == [VARIANTS[tag]]
            fields = row['event'][VARIANTS[tag]]
            assert isinstance(fields['timestamp'], int) and fields['timestamp'] > 0
            if tag == 10:
                # Status remains a two-core report with no invented validator/storage facilities.
                assert fields['num_peers'] in (0, 1) and fields['num_guarantees'] == [0, 0]
                for key in ('num_val_peers', 'num_sync_peers', 'num_shards', 'shards_size',
                            'num_preimages', 'preimages_size'):
                    assert fields[key] == 0, (key, fields)
            elif tag == 21:
                # The post-restart listener generation receives a fresh ID in the advanced namespace.
                if recovered:
                    generation = 1
                    attempts.append(base + offset)
                    assert attempts[1] >= prefix and attempts[1] > original
                assert fields['from'] == {'ipv6': [0] * 10 + [255, 255, 127, 0, 0, 1],
                                          'port': relay_ports[generation]}
            elif tag in (22, 23):
                # Both rejection and success must settle the current generation's own incoming attempt.
                assert fields['connecting_id'] == attempts[generation]
                if tag == 22:
                    assert fields['reason'] == ''
                else:
                    assert bytes(fields['peer_id']).hex() == clients[generation]
            else:
                # Only an authenticated generation may close; strict lifecycle ordering excludes rejection closes.
                assert bytes(fields['peer']).hex() == clients[generation]
                assert fields['terminator'] is None and fields['reason'] == ''
    assert len(attempts) == 2 and any(row['event_type'] == 10 for row in after[1:])
    return dict(attempts=attempts, skipped_prefix=prefix, closes=1 if rejected else 2)


# Settle one pending incoming generation after a real restart, then admit a different identity on the same listener.
def run_incoming(binary, collector, report, folder, rejected):
    from test_quic import fixtures
    from telemetry_incoming import reply_gate
    folder.mkdir(parents=True, exist_ok=True)
    certificates = folder/'certificates'
    fixtures(certificates)
    keys = ('c', 'b') if rejected else ('b', 'c')
    clients = [(certificates/f'{key}.pub').read_bytes().hex() for key in keys]
    server_identity = (certificates/'a.pub').read_bytes().hex()
    telemetry_port, api_port, udp_port = ports()
    shutdown = folder/f'stop-{time.time_ns()}'
    with ExitStack() as owners:
        session = RestartSession(owners, folder, collector, telemetry_port, api_port)
        first = session.backend('collector-before')
        messages = report['before_messages'] = []
        stream = session.subscribe(messages)
        relay = owners.enter_context(RegistrationRelay(('127.0.0.1', telemetry_port)))
        report['registrations'] = relay.registrations
        report['server_identity'], report['clients'] = server_identity, clients
        pin = certificates/'b.pub' if rejected else '-'
        server = session.launch('server', [binary, 'server', '--net-port', udp_port, '--net-cert', certificates/'a.cert.pem',
            '--net-key', certificates/'a.key.pem', '--net-peer-key', pin, '--net-alpn', 'jamnp-s/1/245becfe', '--net-timeout-ms', '60000', '--net-mode', 'service',
            '--chain', ROOT/'tests/fixtures/telemetry-dev.json', '--with-telemetry', '--telemetry', f'127.0.0.1:{relay.port}'],
            env={**os.environ, 'RAGNAROK_SERVICE_STOP': str(shutdown)})
        session.ready(server, 'server')
        deadline = time.monotonic() + 45

        # History covers events racing subscription and remains bounded by the shared collector helper.
        def until(predicate):
            while True:
                rows = session.history(stream, messages, deadline)
                if predicate(rows):
                    return rows
                receive(stream, messages, deadline)

        until(lambda rows: any(row['event_type'] == 10 for row in rows))
        relay_ports, closes = [], 0
        for generation, key in enumerate(keys):
            # Each client has its own UDP source and reply buffer; the server process/listener stays unchanged.
            with reply_gate(udp_port) as (port, released):
                relay_ports.append(port)
                name = f'client-{generation}'
                client = session.launch(name, [binary, 'client', '--net-port', port, '--net-cert', certificates/f'{key}.cert.pem',
                    '--net-key', certificates/f'{key}.key.pem', '--net-peer-key', certificates/'a.pub', '--net-alpn', 'jamnp-s/1/245becfe', '--net-timeout-ms', '30000', '--net-mode', 'mixed'])
                observed = until(lambda rows: any(row['event_type'] == 21 for row in rows))
                if generation == 0:
                    # The held server reply prevents the client's certificate/Finished flight before restart.
                    assert all(row['event_type'] in (10, 21) for row in observed)
                    report['before'] = observed
                    stop(first)
                    assert first.poll() is not None
                    stream.close()
                    second = session.backend('collector-after')
                    messages = report['after_messages'] = []
                    stream = session.subscribe(messages)
                    until(lambda rows: any(row['event_type'] == 0 for row in rows) and
                          any(row['event_type'] == 10 for row in rows))
                released.set()
                failed = rejected and generation == 0
                if failed:
                    # A rejected incoming certificate must settle without an admitted-peer close or exchange.
                    observed = until(lambda rows: any(row['event_type'] == 22 for row in rows))
                    assert client.wait(timeout=8) > 0
                    assert 'EXCHANGE_OK' not in (folder/f'{name}.log').read_text()
                    assert 'AUTH_OK' not in (folder/'server.log').read_text()
                else:
                    # Wait for observed close plus native slot retirement before reusing the listener.
                    closes += 1
                    observed = until(lambda rows: sum(row['event_type'] == 27 for row in rows) == closes)
                    assert client.wait(timeout=8) == 0
                    assert 'EXCHANGE_OK 8' in (folder/f'{name}.log').read_text()
                    idle_deadline = time.monotonic() + 8
                    while f'SERVICE_IDLE {closes} {closes} ' not in (folder/'server.log').read_text():
                        assert server.poll() is None and time.monotonic() < idle_deadline
                        time.sleep(0.02)
        shutdown.touch()
        # Sequential clients intentionally do not satisfy the service profile's separate three-peer peak test.
        assert server.wait(timeout=8) == 2
        assert f'SERVICE_DONE {closes} {closes} 1' in (folder/'server.log').read_text()
        report['after'] = session.history(stream, messages, deadline)
        report['replay'] = verify_incoming(report['before'], report['after'], server_identity,
                                            clients, relay_ports, rejected)
        verify_registrations(relay.registrations, server_identity,
                             json.loads((ROOT/'tests/fixtures/telemetry-dev.json').read_text()))
        assert second.poll() is None
