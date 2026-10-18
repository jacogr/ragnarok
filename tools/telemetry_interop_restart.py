# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Bounded real-collector restart scenario; relays forward opaque bytes without implementing JAM.

Exposes RegistrationRelay, RestartSession and replay/registration validators for bounded
collector restarts.
"""
from contextlib import ExitStack
import hashlib
import json
import select
import socket
import subprocess
import threading
import time
from urllib.error import URLError
from urllib.request import urlopen

from test_telemetry_interop import ROOT, event_rows, ports, receive, stop


# Read one bounded frame, distinguishing a clean connection close from truncation.
def read_frame(connection):
    data = bytearray()
    size = 4
    while len(data) < size:
        # A prefix fixes the allocation bound before the payload is read.
        part = connection.recv(size - len(data))
        if not part:
            assert not data, 'truncated registration relay frame'
            return None
        data.extend(part)
        if len(data) == 4 and size == 4:
            payload = int.from_bytes(data, 'little')
            assert 0 < payload <= 2048, payload
            size += payload
    return bytes(data)


# One joined worker forwards at most one 2048-byte frame at a time and records only registrations.
class RegistrationRelay:
    def __init__(self, destination, ipv6=False):
        """Bind a private loopback listener in the requested family; own its socket and worker until context exit."""
        self.destination = destination
        self.listener = socket.socket(socket.AF_INET6 if ipv6 else socket.AF_INET, socket.SOCK_STREAM)
        self.listener.bind(('::1' if ipv6 else '127.0.0.1', 0))
        self.connections = []
        self.listener.listen(2)
        self.listener.settimeout(0.1)
        self.port = self.listener.getsockname()[1]
        self.finished = threading.Event()
        self.registrations, self.errors = [], []
        self.worker = threading.Thread(target=self.forward, name='registration-relay')

    def __enter__(self):
        """Start forwarding only after the owner has registered context cleanup."""
        self.worker.start()
        return self

    def __exit__(self, *unused):
        """Join the worker before releasing its borrowed listener, including assertion failures."""
        self.finished.set()
        self.worker.join(timeout=7)
        self.listener.close()
        assert not self.worker.is_alive(), 'registration relay did not stop'
        assert not self.errors, self.errors

    def forward(self):
        """Pass exact framed bytes to the selected collector; collector EOF closes the exporter socket."""
        try:
            while not self.finished.is_set():
                # Keep idle accept cancellable without an unbounded connection queue.
                try:
                    incoming, _ = self.listener.accept()
                except socket.timeout:
                    continue
                with incoming:
                    incoming.settimeout(2)
                    try:
                        with socket.create_connection(self.destination, timeout=2) as outgoing:
                            assert len(self.connections) < 4, 'unexpected relay connection loop'
                            self.connections.append(dict(incoming=incoming.getsockname()[0],
                                                         outgoing=outgoing.getpeername()[0]))
                            first = True
                            while not self.finished.is_set():
                                # The collector sends no telemetry replies; EOF propagates its real termination.
                                ready, _, _ = select.select([incoming, outgoing], [], [], 0.1)
                                if outgoing in ready:
                                    assert outgoing.recv(1) == b'', 'unexpected collector reply'
                                    break
                                if incoming in ready:
                                    packet = read_frame(incoming)
                                    if packet is None:
                                        break
                                    if first:
                                        assert len(self.registrations) < 4, 'unexpected reconnect loop'
                                        self.registrations.append(packet[4:].hex())
                                        first = False
                                    outgoing.sendall(packet)
                    except OSError:
                        # Collector refusal/reset during the deliberate outage closes this exporter connection.
                        pass
        except Exception as error:
            self.errors.append(repr(error))


# Validate registration independently from collector acceptance, including chain identity rather than just peer ID.
def verify_registrations(registrations, identity, chain):
    assert len(registrations) == 2 and registrations[0] == registrations[1], 'registration changed on restart'
    hello = bytes.fromhex(registrations[0])
    assert len(hello) > 205 and hello[0] == 1
    assert hello[1:123] == bytes.fromhex(chain['protocol_parameters'])
    assert hello[123:155] == hashlib.blake2b(bytes.fromhex(chain['genesis_header']), digest_size=32).digest()
    assert hello[155:187].hex() == identity


# A fresh collector must cover the old attempt with one dropped prefix and retain its original correlation ID.
def verify_replay(before, after, identities, port):
    identity = identities['client']
    assert before and all(row['node_id'] == identity for row in before)
    attempts = [index for index, row in enumerate(before) if row['event_type'] == 24]
    assert len(attempts) == 1 and all(row['event_type'] in (10, 24) for row in before)
    attempt = attempts[0]
    assert after and after[0]['node_id'] == identity and after[0]['event_type'] == 0
    assert list(after[0]['event']) == ['Dropped']
    dropped = after[0]['event']['Dropped']
    prefix = dropped['num']
    assert isinstance(prefix, int) and len(before) <= prefix < 64
    assert 0 < dropped['timestamp'] <= dropped['last_timestamp']
    assert all(row['node_id'] == identity and row['event_type'] in (10, 26, 27) for row in after[1:])
    lifecycle = [row for row in after[1:] if row['event_type'] != 10]
    assert [row['event_type'] for row in lifecycle] == [26, 27]
    assert lifecycle[0]['event']['ConnectedOut']['connecting_id'] == attempt
    # Validate the original destination and the recovered fields independently of collector-global IDs.
    from test_telemetry_interop import VARIANTS
    dial = before[attempt]['event']['ConnectingOut']['to']
    assert bytes(dial['peer_id']).hex() == identities['server']
    assert dial['peer_address'] == {'ipv6': [0] * 10 + [255, 255, 127, 0, 0, 1], 'port': port}
    for row in after[1:]:
        # Reject malformed variants and false peer accounting even when event tags look correct.
        assert list(row['event']) == [VARIANTS[row['event_type']]]
        fields = row['event'][VARIANTS[row['event_type']]]
        assert fields['timestamp'] > 0
        if row['event_type'] == 10:
            # Re-registration must retain the two-core shape and leave unimplemented facilities empty.
            assert fields['num_peers'] in (0, 1) and fields['num_guarantees'] == [0, 0]
            for key in ('num_val_peers', 'num_sync_peers', 'num_shards', 'shards_size',
                        'num_preimages', 'preimages_size'):
                assert fields[key] == 0, (key, fields)
        elif row['event_type'] == 27:
            assert bytes(fields['peer']).hex() == identities['server']
            assert fields['terminator'] is None and fields['reason'] == ''
    assert any(row['event_type'] == 10 for row in after[1:]), 'missing recovered status'
    return dict(attempt=attempt, skipped_prefix=prefix, recovered_events=len(after))


# Shared child/socket ownership for the incoming and outgoing real-collector restart scenarios.
class RestartSession:
    def __init__(self, owners, folder, collector, telemetry_port, api_port, ipv6=False):
        """Borrow the scenario ExitStack and keep all generated diagnostics in its private directory."""
        self.owners, self.folder, self.collector = owners, folder, collector
        self.telemetry_port, self.api_port = telemetry_port, api_port
        self.telemetry_host = '[::1]' if ipv6 else '127.0.0.1'

    # All logs survive failure; ExitStack reaps every child before closing its output file.
    def launch(self, name, arguments, env=None):
        output = self.owners.enter_context((self.folder/f'{name}.log').open('wb'))
        child = subprocess.Popen([str(arg) for arg in arguments], stdout=output, stderr=subprocess.STDOUT, env=env)
        self.owners.callback(stop, child)
        return child

    # Readiness is the collector's HTTP response, not a startup delay.
    def backend(self, name):
        child = self.launch(name, [self.collector, '--no-database', '--telemetry-bind', f'{self.telemetry_host}:{self.telemetry_port}',
                             '--api-bind', f'127.0.0.1:{self.api_port}', '--ingestion-threads', '0'])
        deadline = time.monotonic() + 15
        while True:
            assert child.poll() is None, name
            try:
                with urlopen(f'http://127.0.0.1:{self.api_port}/api/health', timeout=1) as response:
                    assert response.status == 200
                return child
            except (URLError, TimeoutError):
                assert time.monotonic() < deadline, name
                time.sleep(0.05)

    # Observe subscription acknowledgement before relying on live events; history also covers earlier reconnects.
    def subscribe(self, messages):
        import websocket
        stream = websocket.create_connection(f'ws://127.0.0.1:{self.api_port}/api/ws', timeout=8,
                                             http_no_proxy=['127.0.0.1'])
        self.owners.callback(stream.close)
        stream.send(json.dumps({'type': 'Subscribe', 'filter': {'type': 'All'}}))
        deadline = time.monotonic() + 15
        while receive(stream, messages, deadline)['type'] != 'subscribed':
            pass
        return stream

    # Collector-global history is bounded and returned in event order, including events before subscription.
    def history(self, stream, messages, deadline):
        stream.send(json.dumps({'type': 'GetRecentEvents', 'limit': 64}))
        while True:
            value = receive(stream, messages, deadline)
            if value['type'] == 'recent_events':
                rows = value['data']['events']
                assert value['data']['count'] == len(rows) < 64
                return rows

    # READY proves the UDP listener exists without touching its handshake deadline.
    def ready(self, child, name):
        deadline = time.monotonic() + 10
        while 'READY' not in (self.folder/f'{name}.log').read_text().splitlines():
            assert child.poll() is None and time.monotonic() < deadline, name
            time.sleep(0.02)


# Complete a pending dial after restarting the real collector; prove separate peer work during its absence.
def run_restart(binary, collector, report, folder, ipv6=False):
    from test_quic import fixtures
    folder.mkdir(parents=True, exist_ok=True)
    certificates = folder/'certificates'
    fixtures(certificates)
    identities = {role: (certificates/f'{key}.pub').read_bytes().hex()
                  for role, key in (('server', 'a'), ('client', 'b'))}
    telemetry_port, api_port, udp_port = ports(ipv6=ipv6)
    host = '::1' if ipv6 else '127.0.0.1'
    cli_host = '[::1]' if ipv6 else host
    report['telemetry_host'] = host
    with ExitStack() as owners:
        session = RestartSession(owners, folder, collector, telemetry_port, api_port, ipv6=ipv6)
        launch, backend = session.launch, session.backend
        subscribe, history, ready = session.subscribe, session.history, session.ready

        first = backend('collector-before')
        messages = report['before_messages'] = []
        stream = subscribe(messages)
        relay = owners.enter_context(RegistrationRelay((host, telemetry_port), ipv6=ipv6))
        report['registrations'] = relay.registrations
        report['relay_connections'] = relay.connections
        report['identities'] = identities
        controls = ['--chain', ROOT/'tests/fixtures/telemetry-dev.json', '--telemetry', f'{cli_host}:{relay.port}']
        gate = owners.enter_context(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
        gate.bind(('127.0.0.1', 0))
        gate.settimeout(0.1)
        server = launch('server', [binary, 'server', udp_port, certificates/'a.cert.pem', certificates/'a.key.pem',
                                  certificates/'b.pub', 'jamnp-s/1/245becfe', '60000'])
        ready(server, 'server')
        client = launch('client', [binary, 'client', gate.getsockname()[1], certificates/'b.cert.pem',
                                  certificates/'b.key.pem', certificates/'a.pub', 'jamnp-s/1/245becfe',
                                  '60000', 'clean', *controls])
        deadline = time.monotonic() + 15
        before = []
        while not any(row['event_type'] == 24 for row in before):
            before.extend(event_rows(receive(stream, messages, deadline)))
            assert len(before) < 64
        report['before'] = history(stream, messages, deadline)
        stop(first)
        assert first.poll() is not None
        stream.close()
        # A separate telemetry-enabled exchange must finish while the collector remains stopped.
        _, _, outage_port = ports()
        outage_controls = ['--chain', ROOT/'tests/fixtures/telemetry-dev.json',
                           '--telemetry', f'{cli_host}:{telemetry_port}']
        outage_server = launch('outage-server', [binary, 'server', outage_port, certificates/'a.cert.pem',
            certificates/'a.key.pem', certificates/'b.pub', 'jamnp-s/1/245becfe', '15000', *outage_controls])
        ready(outage_server, 'outage-server')
        outage_client = launch('outage-client', [binary, 'client', outage_port, certificates/'b.cert.pem',
            certificates/'b.key.pem', certificates/'a.pub', 'jamnp-s/1/245becfe', '6000', 'clean', *outage_controls])
        assert outage_client.wait(timeout=10) == outage_server.wait(timeout=10) == 0
        report['outage_exchanged_requests'] = 8
        assert client.poll() is None and server.poll() is None, 'pending peers did not survive outage'
        second = backend('collector-after')
        messages = report['after_messages'] = []
        stream = subscribe(messages)
        deadline = time.monotonic() + 25
        while True:
            # Poll retained history to cover reconnects racing with WebSocket subscription establishment.
            after = history(stream, messages, deadline)
            if any(row['event_type'] == 0 for row in after) and any(row['event_type'] == 10 for row in after):
                break
            receive(stream, messages, deadline)
        finished, errors = threading.Event(), []

        # Release the pending QUIC dial only after the new collector accepted its dropped prefix and status.
        def forward_udp():
            source = None
            remote = ('127.0.0.1', udp_port)
            try:
                while not finished.is_set():
                    try:
                        packet, address = gate.recvfrom(65535)
                    except socket.timeout:
                        continue
                    if address == remote:
                        assert source is not None
                        gate.sendto(packet, source)
                    else:
                        if source is None:
                            source = address
                        assert address == source
                        gate.sendto(packet, remote)
            except Exception as error:
                errors.append(repr(error))

        worker = threading.Thread(target=forward_udp, name='restart-udp-relay')
        worker.start()
        try:
            while not any(row['event_type'] == 27 for row in after):
                after.extend(event_rows(receive(stream, messages, deadline)))
                assert len(after) < 64
            assert client.wait(timeout=8) == server.wait(timeout=8) == 0
        finally:
            # Never release a socket borrowed by a live relay worker, including assertion-failure cleanup.
            finished.set()
            worker.join(timeout=2)
            assert not worker.is_alive(), 'UDP relay did not stop'
        assert not errors, errors
        report['after'] = history(stream, messages, deadline)
        report['replay'] = verify_replay(report['before'], report['after'], identities, gate.getsockname()[1])
        report['registrations'] = list(relay.registrations)
        report['relay_connections'] = list(relay.connections)
        assert report['relay_connections'] == [dict(incoming=host, outgoing=host)] * 2
        verify_registrations(report['registrations'], identities['client'],
                             json.loads((ROOT/'tests/fixtures/telemetry-dev.json').read_text()))
        for role in ('server', 'client', 'outage-server', 'outage-client'):
            assert 'EXCHANGE_OK 8' in (folder/f'{role}.log').read_text(), role
        assert second.poll() is None
