"""Bounded real TCP collector tests, including actual proof-peer CLI registration."""
import hashlib
import json
import socket
import select
import struct
import subprocess


# Read an exact frame even when TCP splits prefixes/payloads; reject oversized test input.
def frame(connection):
    def read(size):
        data = bytearray()
        while len(data) < size:
            # Small reads deliberately exercise collector-side fragmentation of native writes.
            part = connection.recv(min(7, size - len(data)))
            if not part:
                raise AssertionError('telemetry EOF before complete frame')
            data.extend(part)
        return bytes(data)
    size = int.from_bytes(read(4), 'little')
    assert 0 < size <= 2048, size
    return read(size)


# Bind only loopback; closing this context releases the collector even after assertion failures.
def listener():
    server = socket.socket()
    server.bind(('127.0.0.1', 0))
    server.listen(4)
    server.settimeout(12)
    return server


# Ensure bounded test children cannot outlive a failed collector assertion.
def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            # Forced cleanup is a harness last resort, never the success path.
            process.kill()
            process.communicate()


# A collector reset must cause a fresh registration, then new status frames, without killing the peer.
def reconnect(binary):
    with listener() as server:
        endpoint = f'127.0.0.1:{server.getsockname()[1]}'
        process = subprocess.Popen([str(binary), endpoint], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            first, _ = server.accept()
            with first:
                first.settimeout(5)
                hello = frame(first)
                assert hello[0] == 1 and hello[25:27] == b'\x02\0'
                attempt = frame(first)
                assert attempt[8] == 24 # The driver emits attempt ID zero before its first status.
                status = frame(first)
                assert len(status) == 43 and status[8] == 10
                assert struct.unpack_from('<I', status, 9)[0] == 7
                # RST exercises SIGPIPE/error isolation and retry timing on both supported hosts.
                first.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
            second, _ = server.accept()
            with second:
                second.settimeout(5)
                assert frame(second) == hello
                skipped = frame(second)
                assert skipped[8] == 0 and int.from_bytes(skipped[17:25], 'little') >= 2
                outcome = frame(second)
                assert outcome[8] == 26 and int.from_bytes(outcome[9:17], 'little') == 0
                assert frame(second)[8] == 10
            stdout, stderr = process.communicate(timeout=5)
            assert process.returncode == 0, (stdout, stderr)
        finally:
            # Keep cleanup independent of success, decode errors and socket timeouts.
            stop(process)
    return dict(passed=True, registrations=2, statuses=2)


# Start a real proof peer, observe its local identity and empty status, then complete normal CE traffic.
def peer_registration(binary, certificates, chain, folder):
    folder.mkdir(parents=True, exist_ok=True)
    assert hashlib.sha256(chain.read_bytes()).hexdigest() == "c0e0dab1c242becf8ec2aa06916c74a3dc84ff9aca1c08a5df217a4d6bc4b1c3"
    spec = json.loads(chain.read_text())
    genesis = hashlib.blake2b(bytes.fromhex(spec['genesis_header']), digest_size=32).digest()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    alpn = 'jamnp-s/1/' + genesis.hex()[:8]
    with listener() as server:
        endpoint = f'127.0.0.1:{server.getsockname()[1]}'
        args = [str(binary), 'server', str(port), str(certificates/'a.cert.pem'),
                str(certificates/'a.key.pem'), str(certificates/'b.pub'), alpn, '7000',
                '--chain', str(chain), '--telemetry', endpoint]
        process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            connection, _ = server.accept()
            with connection:
                connection.settimeout(5)
                hello = frame(connection)
                assert hello[0] == 1
                assert hello[1:123] == bytes.fromhex(spec['protocol_parameters'])
                assert hello[123:155] == genesis
                assert hello[155:187] == (certificates/'a.pub').read_bytes()
                assert hello[187:203] == bytes.fromhex('00000000000000000000ffff7f000001')
                assert int.from_bytes(hello[203:205], 'little') == port
                status = frame(connection)
                assert status[8] == 10 and int.from_bytes(status[9:13], 'little') == 0
                client = subprocess.run([str(binary), 'client', str(port),
                    str(certificates/'b.cert.pem'), str(certificates/'b.key.pem'),
                    str(certificates/'a.pub'), alpn, '3000', 'clean', '--telemetry', endpoint,
                    '--chain', str(chain)], capture_output=True, timeout=6)
                assert client.returncode == 0, (client.stdout, client.stderr)
                outgoing, _ = server.accept()
                with outgoing:
                    outgoing.settimeout(5)
                    assert frame(outgoing)[0] == 1
                    dialing = frame(outgoing)
                    assert dialing[8] == 24 and dialing[9:41] == (certificates/'a.pub').read_bytes()
                    assert dialing[41:57] == bytes.fromhex('00000000000000000000ffff7f000001')
                    assert int.from_bytes(dialing[57:59], 'little') == port
                    connected = frame(outgoing)
                    assert connected[8] == 26 and int.from_bytes(connected[9:17], 'little') == 0
                    closed = frame(outgoing)
                    assert closed[8] == 27 and closed[9:41] == (certificates/'a.pub').read_bytes()
                    assert closed[41:] == b'\0\0' # Unknown terminator and reason remain explicitly absent.
                    assert outgoing.recv(1) == b'' # Exactly one closure, followed by exporter shutdown.
                incoming = frame(connection)
                assert incoming[8] == 21 and incoming[9:25] == bytes.fromhex('00000000000000000000ffff7f000001')
                assert int.from_bytes(incoming[25:27], 'little') > 0
                accepted = frame(connection)
                assert accepted[8] == 23 and int.from_bytes(accepted[9:17], 'little') == 1
                assert accepted[17:] == (certificates/'b.pub').read_bytes()
                assert connection.recv(1) == b'' # Successful SSL destruction cannot emit a second terminal outcome.
            stdout, stderr = process.communicate(timeout=5)
            (folder/'peer.log').write_bytes(stdout + stderr)
            assert process.returncode == 0 and b'EXCHANGE_OK 8' in stdout, (stdout, stderr)
        finally:
            # A failed handshake must not leave the UDP listener or TCP exporter behind.
            stop(process)
    return dict(passed=True, genesis=genesis.hex(), identity='local certificate', peers_before_connect=0)


# An unresponsive destination settles as a failed attempt, with no invented TLS reason or success event.
def dial_failure(binary, certificates, chain, folder):
    folder.mkdir(parents=True, exist_ok=True)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as silent:
        silent.bind(('127.0.0.1', 0))
        with listener() as collector:
            endpoint = f'127.0.0.1:{collector.getsockname()[1]}'
            process = subprocess.Popen([str(binary), 'client', str(silent.getsockname()[1]),
                str(certificates/'b.cert.pem'), str(certificates/'b.key.pem'), str(certificates/'a.pub'),
                'jamnp-s/1/245becfe', '500', '--telemetry', endpoint, '--chain', str(chain)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                connection, _ = collector.accept()
                with connection:
                    connection.settimeout(5)
                    assert frame(connection)[0] == 1
                    assert frame(connection)[8] == 24
                    failed = frame(connection)
                    assert failed[8] == 25 and failed[9:17] == bytes(8) and failed[17:] == b'\0'
                    assert connection.recv(1) == b'' # Failed authentication must not invent a disconnected peer.
                stdout, stderr = process.communicate(timeout=5)
                (folder/'failed-dial.log').write_bytes(stdout + stderr)
                assert process.returncode != 0 and b'AUTH_OK' not in stdout
            finally:
                # Always release the bounded dialer, even on failed framing assertions.
                stop(process)
    return dict(passed=True, attempt=0, outcome='failed', reason='unknown')


# A remote process loss closes an authenticated idle connection through the native two-second expiry.
def peer_loss(binary, certificates, chain, folder):
    folder.mkdir(parents=True, exist_ok=True)
    with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as reservation:
        reservation.bind(('::1', 0))
        port = reservation.getsockname()[1]
    server = subprocess.Popen([str(binary), 'server', str(port), str(certificates/'a.cert.pem'),
        str(certificates/'a.key.pem'), str(certificates/'b.pub'), 'jamnp-s/1/245becfe', '800', 'idle'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        assert select.select([server.stdout], [], [], 5)[0], 'peer listener did not become ready'
        assert server.stdout.readline().strip() == b'READY'
        with listener() as collector:
            endpoint = f'127.0.0.1:{collector.getsockname()[1]}'
            client = subprocess.Popen([str(binary), 'client', str(port), str(certificates/'b.cert.pem'),
                str(certificates/'b.key.pem'), str(certificates/'a.pub'), 'jamnp-s/1/245becfe',
                '6000', 'idle', '--chain', str(chain), '--telemetry', endpoint],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                connection, _ = collector.accept()
                with connection:
                    connection.settimeout(8)
                    assert frame(connection)[0] == 1
                    attempt = frame(connection)
                    assert attempt[8] == 24 and attempt[41:57] == bytes(15) + b'\1'
                    connected = frame(connection)
                    assert connected[8] == 26 and connected[9:17] == bytes(8)
                    closed = None
                    for _ in range(4):
                        # Status can precede expiry; no failed-attempt event may replace authenticated closure.
                        event = frame(connection)
                        assert event[8] in (10, 27)
                        if event[8] == 27:
                            closed = event
                            break
                    assert closed is not None and closed[9:41] == (certificates/'a.pub').read_bytes()
                    assert closed[41:] == b'\0\0'
                    assert connection.recv(1) == b'' # Closure is emitted once, not for each polling turn.
                stdout, stderr = client.communicate(timeout=5)
                (folder/'lost-peer-client.log').write_bytes(stdout + stderr)
                assert client.returncode != 0 and b'AUTH_OK' in stdout and b'CONNECTION_CLOSED' in stdout
            finally:
                # Client cleanup remains bounded if the collector detects a malformed event.
                stop(client)
        stdout, stderr = server.communicate(timeout=5)
        (folder/'lost-peer-server.log').write_bytes(stdout + stderr)
        assert server.returncode != 0 and b'AUTH_OK' in stdout
    finally:
        # The silent application peer must never survive a failed telemetry assertion.
        stop(server)
    return dict(passed=True, address='::1', disconnects=1, application_exchange='incomplete')


# Reject a real certificate against the server pin and settle the incoming attempt during native teardown.
def incoming_failure(binary, certificates, chain, folder):
    folder.mkdir(parents=True, exist_ok=True)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    with listener() as collector:
        endpoint = f'127.0.0.1:{collector.getsockname()[1]}'
        server = subprocess.Popen([str(binary), 'server', str(port), str(certificates/'a.cert.pem'),
            str(certificates/'a.key.pem'), str(certificates/'a.pub'), 'jamnp-s/1/245becfe', '1500',
            '--chain', str(chain), '--telemetry', endpoint], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            connection, _ = collector.accept()
            with connection:
                connection.settimeout(5)
                assert frame(connection)[0] == 1
                client = subprocess.run([str(binary), 'client', str(port), str(certificates/'b.cert.pem'),
                    str(certificates/'b.key.pem'), str(certificates/'a.pub'), 'jamnp-s/1/245becfe',
                    '1800', 'clean'], capture_output=True, timeout=5)
                assert client.returncode != 0
                attempt = None
                for event_id in range(4):
                    # Status timing may vary; failure must reference the actual incoming event position.
                    event = frame(connection)
                    if event[8] == 21:
                        assert attempt is None
                        attempt = event_id
                    elif event[8] == 22:
                        assert attempt is not None and int.from_bytes(event[9:17], 'little') == attempt
                        assert event[17:] == b'\0'
                        break
                    else:
                        assert event[8] == 10 # Neither an authenticated identity nor a disconnect may be invented.
                else:
                    raise AssertionError('incoming failure was not observed')
                assert connection.recv(1) == b''
            stdout, stderr = server.communicate(timeout=5)
            (folder/'incoming-failure.log').write_bytes(stdout + stderr)
            assert server.returncode != 0 and b'AUTH_OK' not in stdout
        finally:
            # TLS and collector failures still retire every test process.
            stop(server)
    return dict(passed=True, outcome='failed', reason='unknown')
