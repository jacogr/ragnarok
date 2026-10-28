# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Real collector decoding of connection-capacity refusal and recovery on one retained listener.

Exposes verify_capacity and run_capacity for collector-observed capacity refusal and slot
recovery.
"""
from contextlib import ExitStack
import os
import time
from test_telemetry_interop import ROOT, VARIANTS, ports, receive
from telemetry_interop_restart import RestartSession


# Require the complete ordered lifecycle; native admission and decoded metadata are independent evidence.
def verify_capacity(events, identities):
    assert 0 < len(events) < 64
    variants = {**VARIANTS, 20: 'ConnectionRefused'}
    lifecycle, starts, statuses = [], [], []
    expected = [21, 23] * 17 + [20, 27, 21, 23, 27]
    closes = []
    for position, row in enumerate(events):
        # Only the retained listener exports into this private collector.
        assert row['node_id'] == identities['server']
        tag = row['event_type']
        assert tag in (10, 20, 21, 23, 27) and list(row['event']) == [variants[tag]]
        fields = row['event'][variants[tag]]
        assert isinstance(fields['timestamp'], int) and fields['timestamp'] > 0
        if tag == 10:
            # Status counts admitted connections and retains the explicit two-core chain shape.
            assert 0 <= fields['num_peers'] <= 16 and fields['num_guarantees'] == [0, 0]
            for key in ('num_val_peers', 'num_sync_peers', 'num_shards', 'shards_size',
                        'num_preimages', 'preimages_size'):
                assert fields[key] == 0, (key, fields)
            statuses.append(fields['num_peers'])
            continue
        lifecycle.append(tag)
        if tag == 21:
            # Every attempt has a real IPv6 loopback source, including the refused connection.
            address = fields['from']
            assert address['ipv6'] == [0] * 15 + [1] and 0 < address['port'] <= 65535
            starts.append((position, address))
        elif tag == 23:
            # The excess peer authenticates before native capacity admission rejects it.
            assert starts and fields['connecting_id'] == starts[-1][0]
            role = 'held' if len(starts) <= 16 else ('refused' if len(starts) == 17 else 'recovered')
            assert bytes(fields['peer_id']).hex() == identities[role]
        elif tag == 20:
            # Refusal must name the seventeenth attempt's endpoint, not an admitted peer's address.
            assert len(starts) == 17 and fields['from'] == starts[16][1]
        else:
            # Only the deliberately released holder and the successful recovery client may close.
            closes.append(bytes(fields['peer']).hex())
            assert fields['terminator'] is None and fields['reason'] == ''
    assert lifecycle == expected, lifecycle
    assert closes == [identities['held'], identities['recovered']], closes
    assert 16 in statuses and statuses[-1] == 15, statuses
    return dict(attempts=18, authenticated=18, refused=1, admitted=17, observed_closes=2)


# Use native admission barriers before each dial, then preserve the other fifteen connections during recovery.
def run_capacity(binary, collector, report, folder):
    from test_quic import fixtures
    from test_quic_resilience import states
    folder.mkdir(parents=True, exist_ok=True)
    certificates = folder/'certificates'
    fixtures(certificates)
    identities = {role: (certificates/f'{key}.pub').read_bytes().hex()
                  for role, key in (('server', 'a'), ('held', 'b'), ('refused', 'c'), ('recovered', 'd'))}
    telemetry_port, api_port, udp_port = ports()
    shutdown = folder/f'stop-{time.time_ns()}'
    with ExitStack() as owners:
        session = RestartSession(owners, folder, collector, telemetry_port, api_port)
        backend = session.backend('collector')
        messages = report['messages'] = []
        stream = session.subscribe(messages)
        server = session.launch('server', [binary, 'server', '--net-port', udp_port, '--net-cert', certificates/'a.cert.pem',
            '--net-key', certificates/'a.key.pem', '--net-peer-key', '-', '--net-alpn', 'jamnp-s/1/245becfe', '--net-timeout-ms', '60000', '--net-mode', 'overload',
            '--chain', ROOT/'tests/fixtures/telemetry-dev.json', '--with-telemetry', '--telemetry-endpoint', f'127.0.0.1:{telemetry_port}'],
            env={**os.environ, 'RAGNAROK_SERVICE_STOP': str(shutdown)})
        session.ready(server, 'server')
        deadline = time.monotonic() + 45

        # The latest native counters establish admission/retirement rather than TLS telemetry alone.
        def state(predicate):
            while True:
                assert server.poll() is None and time.monotonic() < deadline
                rows = states((folder/'server.log').read_text())
                if rows and predicate(rows[-1]):
                    return rows[-1]
                time.sleep(0.02)

        # Collector history covers events before live subscription delivery without losing their local positions.
        def observed(predicate):
            while True:
                rows = session.history(stream, messages, deadline)
                if predicate(rows):
                    return rows
                receive(stream, messages, deadline)

        # All clients are nonblocking native peers; telemetry is emitted only by the server under test.
        def client(name, key, mode):
            return session.launch(name, [binary, 'client', '--net-port', udp_port, '--net-cert', certificates/f'{key}.cert.pem',
                '--net-key', certificates/f'{key}.key.pem', '--net-peer-key', certificates/'a.pub', '--net-alpn', 'jamnp-s/1/245becfe', '--net-timeout-ms', '60000', '--net-mode', mode])

        held = []
        for index in range(16):
            # Fill exactly one new slot at a time to make refusal attribution unambiguous.
            held.append(client(f'held-{index}', 'b', 'idle'))
            state(lambda row: row[0] == index + 1 and row[2] == 0)
        observed(lambda rows: any(row['event_type'] == 10 and row['event']['Status']['num_peers'] == 16
                                  for row in rows))
        excess = client('refused', 'c', 'probe')
        report['full_state'] = state(lambda row: row[0] == 16 and row[2] == 1)
        observed(lambda rows: any(row['event_type'] == 20 for row in rows))
        assert excess.wait(timeout=8) == 2
        assert 'EXCHANGE_OK' not in (folder/'refused.log').read_text()
        assert all(child.poll() is None for child in held)
        held[0].kill()
        held[0].wait(timeout=5)
        report['released_state'] = state(lambda row: row[0] == 15 and row[2] == 1)
        observed(lambda rows: sum(row['event_type'] == 27 for row in rows) == 1)
        recovered = client('recovered', 'd', 'probe')
        assert recovered.wait(timeout=8) == 0
        assert 'EXCHANGE_OK 1' in (folder/'recovered.log').read_text()
        state(lambda row: row[0] == 15 and row[2] == 1)
        observed(lambda rows: sum(row['event_type'] == 27 for row in rows) == 2 and
                 rows[-1]['event_type'] == 10 and rows[-1]['event']['Status']['num_peers'] == 15)
        assert all(child.poll() is None for child in held[1:]), 'admitted peers displaced'
        shutdown.touch()
        # Live holders intentionally make graceful all-peers-retired service shutdown false; destruction adds no closes.
        assert server.wait(timeout=8) == 2
        assert 'SERVICE_DONE 17 2 16' in (folder/'server.log').read_text()
        report['events'] = session.history(stream, messages, deadline)
        report['identities'] = identities
        report['capacity'] = verify_capacity(report['events'], identities)
        assert backend.poll() is None
