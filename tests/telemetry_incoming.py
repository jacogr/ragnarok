# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Real incoming TLS callbacks across collector resets, with opaque UDP reply gating."""
from contextlib import ExitStack, contextmanager
import json
import os
import socket
import struct
import subprocess
import threading
import time
from telemetry_checks import EventCapture, frame, listener, stop
from test_quic_resilience import watch


# Own one IPv4 relay and joined worker; hold bounded server replies until the caller opens the gate.
@contextmanager
def reply_gate(port):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as gate:
        gate.bind(('127.0.0.1', 0))
        gate.settimeout(0.1)
        released, finished = threading.Event(), threading.Event()
        errors = []

        # Forward a single pinned client's opaque packets without interpreting QUIC, TLS or JAM bytes.
        def relay():
            remote = ('127.0.0.1', port)
            source = None
            pending, pending_bytes = [], 0
            try:
                # A finite receive timeout bounds cancellation and releases the bounded first-flight buffer.
                while not finished.is_set():
                    if released.is_set() and pending:
                        # Deliver withheld flights immediately instead of racing QUIC's retransmission backoff.
                        for packet in pending:
                            gate.sendto(packet, source)
                        pending.clear()
                        pending_bytes = 0
                    try:
                        packet, address = gate.recvfrom(65535)
                    except socket.timeout:
                        continue # Recheck cancellation even when the peer sends nothing.
                    if address[:2] == remote:
                        # Withhold replies so the client cannot produce the certificate/Finished flight.
                        if released.is_set():
                            assert source is not None
                            gate.sendto(packet, source)
                        else:
                            # Fixture traffic is tiny; overflow is a test failure, never an unbounded buffer.
                            assert len(pending) < 64 and pending_bytes + len(packet) <= 128 * 1024
                            pending.append(packet)
                            pending_bytes += len(packet)
                    else:
                        # Pin the first client endpoint; later generations use their own relay socket.
                        if source is None:
                            source = address
                        assert address == source, address
                        gate.sendto(packet, remote)
            except (AssertionError, OSError) as error:
                errors.append(repr(error)) # Return worker failures to the scenario's assertion path.

        worker = threading.Thread(target=relay, name='incoming-telemetry-reply-gate')
        worker.start()
        try:
            yield gate.getsockname()[1], released
        finally:
            # Join before closing the borrowed socket, including failures before the traffic gate opens.
            finished.set()
            worker.join(timeout=2)
            assert not worker.is_alive(), 'incoming UDP relay failed to stop'
        assert not errors, errors


# Reset during a real incoming handshake, settle it, then authenticate a fresh generation on the same listener.
def incoming_reconnect(binary, certificates, chain, folder, rejected=False):
    folder.mkdir(parents=True, exist_ok=True)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    shutdown = folder/f'stop-{time.time_ns()}'
    attempts, outcomes, closes = [], [], 0
    with ExitStack() as owners:
        collector = owners.enter_context(listener())
        output = owners.enter_context((folder/'server.log').open('wb'))
        pin = str(certificates/'b.pub') if rejected else '-'
        server = subprocess.Popen([str(binary), 'server', str(port), str(certificates/'a.cert.pem'),
            str(certificates/'a.key.pem'), pin, 'jamnp-s/1/245becfe', '60000', 'service',
            '--chain', str(chain), '--telemetry', f'127.0.0.1:{collector.getsockname()[1]}'],
            stdout=output, stderr=subprocess.STDOUT,
            env={**os.environ, 'RAGNAROK_SERVICE_STOP': str(shutdown)})
        owners.callback(stop, server)
        watch({'server': server}, {'server': folder/'server.log'},
              {'server': lambda text: 'READY' in text.splitlines()}, {'server': {}},
              seconds=5, thread_limits={'server': 1})
        connection, _ = collector.accept()
        owners.enter_context(connection)
        connection.settimeout(12)
        hello = frame(connection)
        assert hello[0] == 1 and hello[155:187] == (certificates/'a.pub').read_bytes()
        capture = EventCapture(connection)
        # A second identity after success, or the allowed identity after rejection, detects stale generations.
        identities = ('c', 'b') if rejected else ('b', 'c')
        for generation, identity in enumerate(identities):
            with reply_gate(port) as (relay_port, released):
                log = folder/f'client-{generation}.log'
                output = owners.enter_context(log.open('wb'))
                client = subprocess.Popen([str(binary), 'client', str(relay_port),
                    str(certificates/f'{identity}.cert.pem'), str(certificates/f'{identity}.key.pem'),
                    str(certificates/'a.pub'), 'jamnp-s/1/245becfe', '30000', 'mixed'],
                    stdout=output, stderr=subprocess.STDOUT)
                owners.callback(stop, client)
                attempt_id, attempt = capture.lifecycle(21)
                assert attempt[9:25] == bytes.fromhex('00000000000000000000ffff7f000001')
                assert int.from_bytes(attempt[25:27], 'little') == relay_port
                assert not attempts or attempt_id > attempts[-1], (attempts, attempt_id)
                attempts.append(attempt_id)
                if generation == 0:
                    # Reply suppression proves TLS cannot have completed before the collector reset.
                    connection.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
                    connection.close()
                    connection, _ = collector.accept()
                    owners.enter_context(connection)
                    connection.settimeout(12)
                    assert frame(connection) == hello
                    skipped = frame(connection)
                    assert len(skipped) == 25 and skipped[8] == 0, skipped.hex()
                    prefix = int.from_bytes(skipped[17:25], 'little')
                    assert attempt_id < prefix < 128, (attempt_id, prefix)
                    capture = EventCapture(connection)
                    capture.position = prefix
                released.set() # Only the recovered collector can observe the ensuing terminal callback.
                failed = rejected and generation == 0
                outcome_id, outcome = capture.lifecycle(22 if failed else 23)
                assert int.from_bytes(outcome[9:17], 'little') == attempt_id
                outcomes.append(outcome_id)
                if failed:
                    # Rejection must not create an authenticated peer or a disconnected event.
                    assert outcome[17:] == b'\0'
                    assert client.wait(timeout=5) != 0
                    assert 'EXCHANGE_OK' not in log.read_text()
                    assert 'AUTH_OK' not in (folder/'server.log').read_text()
                else:
                    # Authentication must also lead to the existing mixed CE exchange and a real close.
                    assert outcome[17:] == (certificates/f'{identity}.pub').read_bytes()
                    _, closed = capture.lifecycle(27)
                    assert closed[9:41] == (certificates/f'{identity}.pub').read_bytes()
                    assert closed[41:] == b'\0\0'
                    assert client.wait(timeout=5) == 0, log.read_text()
                    assert 'EXCHANGE_OK 8' in log.read_text()
                    closes += 1
                    # Native idle counters establish retirement before the next listener generation starts.
                    watch({'server': server}, {'server': folder/'server.log'},
                          {'server': lambda text: f'SERVICE_IDLE {closes} {closes} ' in text},
                          {'server': {}}, seconds=5, thread_limits={'server': 1})
        shutdown.touch()
        capture.end() # No extra failure, loss, success or close may hide after either terminal outcome.
        # The service's separate three-peer peak gate is intentionally unmet by this sequential case.
        assert server.wait(timeout=5) == 2
        assert f'SERVICE_DONE {closes} {closes} 1' in (folder/'server.log').read_text()
    result = dict(passed=True, rejected=rejected, attempts=attempts, outcomes=outcomes,
                  skipped_prefix=prefix, closes=closes, registrations=2)
    (folder/'reconnect.json').write_text(json.dumps(result, indent=2) + '\n')
    return result
