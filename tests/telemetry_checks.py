"""Bounded real TCP collector tests, including actual proof-peer CLI registration."""
import hashlib
import os
import time
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
def listener(ipv6=False):
    server = socket.socket(socket.AF_INET6 if ipv6 else socket.AF_INET)
    server.bind(('::1' if ipv6 else '127.0.0.1', 0))
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
def reconnect(binary, ipv6=False):
    with listener(ipv6) as server:
        host = '[::1]' if ipv6 else '127.0.0.1'
        endpoint = f'{host}:{server.getsockname()[1]}'
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
def peer_registration(binary, certificates, chain, folder, ipv6=False):
    folder.mkdir(parents=True, exist_ok=True)
    assert hashlib.sha256(chain.read_bytes()).hexdigest() == "c0e0dab1c242becf8ec2aa06916c74a3dc84ff9aca1c08a5df217a4d6bc4b1c3"
    spec = json.loads(chain.read_text())
    genesis = hashlib.blake2b(bytes.fromhex(spec['genesis_header']), digest_size=32).digest()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    alpn = 'jamnp-s/1/' + genesis.hex()[:8]
    with listener(ipv6) as server:
        host = '[::1]' if ipv6 else '127.0.0.1'
        endpoint = f'{host}:{server.getsockname()[1]}'
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
                closed = frame(connection)
                assert closed[8] == 27 and closed[9:41] == (certificates/'b.pub').read_bytes()
                assert closed[41:] == b'\0\0'
                assert connection.recv(1) == b'' # One real incoming close, with no duplicate during destruction.
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
        str(certificates/'a.key.pem'), str(certificates/'b.pub'), 'jamnp-s/1/245becfe', '30000', 'idle'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
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
                    assert select.select([server.stdout], [], [], 5)[0], 'server authentication did not complete'
                    assert server.stdout.readline().strip() == b'AUTH_OK'
                    server.kill() # Trigger expiry only after both sides really authenticated.
                    assert server.wait(timeout=5) == -9
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
        assert server.returncode == -9 # Authentication was consumed before the deliberate process loss.
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


# A retained IPv6 listener reports each expired peer's own identity, and never fabricates a teardown close.
def incoming_lifetimes(binary, certificates, chain, folder, remote_loss, startup_delay=0):
    folder.mkdir(parents=True, exist_ok=True)
    with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as reservation:
        reservation.bind(('::1', 0))
        port = reservation.getsockname()[1]
    children = []
    stop_gate = folder/f'incoming-stop-{time.time_ns()}'
    # Each child owns a distinct authenticated identity; the second reuses the first peer's retired slot.
    def launch(identity):
        child = subprocess.Popen([str(binary), 'client', str(port), str(certificates/f'{identity}.cert.pem'),
            str(certificates/f'{identity}.key.pem'), str(certificates/'a.pub'), 'jamnp-s/1/245becfe',
            '30000', 'idle'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        children.append(child)
    with listener() as collector:
        endpoint = f'127.0.0.1:{collector.getsockname()[1]}'
        server = subprocess.Popen([str(binary), 'server', str(port), str(certificates/'a.cert.pem'),
            str(certificates/'a.key.pem'), '-', 'jamnp-s/1/245becfe', '30000',
            'overload', '--chain', str(chain), '--telemetry', endpoint], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env={**os.environ, 'RAGNAROK_SERVICE_STOP': str(stop_gate)})
        try:
            connection, _ = collector.accept()
            with connection:
                connection.settimeout(12)
                assert frame(connection)[0] == 1
                if startup_delay:
                    # Regression: delay beyond the former 1.2-second server lifetime before starting the peer.
                    time.sleep(startup_delay)
                launch('b')
                starts, successes, closes = [], [], []
                for event_id in range(16):
                    # EOF is valid only between complete frames; every observed frame remains bounded.
                    if not connection.recv(1, socket.MSG_PEEK):
                        break
                    event = frame(connection)
                    if event[8] == 21:
                        assert event[9:25] == bytes(15) + b'\1'
                        starts.append(event_id)
                    elif event[8] == 23:
                        assert len(starts) == len(successes) + 1
                        assert int.from_bytes(event[9:17], 'little') == starts[-1]
                        expected = 'b' if not successes else 'c'
                        assert event[17:] == (certificates/f'{expected}.pub').read_bytes()
                        successes.append(event[17:])
                        if remote_loss:
                            # Kill only after authenticated identity is observed; startup speed cannot consume the lifetime.
                            children[-1].kill()
                            assert children[-1].wait(timeout=5) == -9
                        else:
                            stop_gate.touch() # Destroy the listener with a confirmed live authenticated peer.
                    elif event[8] == 27:
                        assert remote_loss and len(closes) < len(successes)
                        assert event[9:41] == successes[len(closes)] and event[41:] == b'\0\0'
                        closes.append(event[9:41])
                        if len(closes) == 1:
                            launch('c') # Reuse the listener after actual expiry, without rebuilding its engine.
                        else:
                            stop_gate.touch() # Both expiry observations arrived before shutting down the listener.
                    else:
                        assert event[8] == 10 # No failure/drop event can substitute for an authenticated close.
                else:
                    raise AssertionError('unbounded incoming telemetry stream')
                assert len(successes) == (2 if remote_loss else 1)
                assert len(closes) == (2 if remote_loss else 0)
                if not remote_loss:
                    assert children[0].poll() is None # The remote is still alive when the server retires.
            stdout, stderr = server.communicate(timeout=3)
            (folder/('incoming-expiry.log' if remote_loss else 'incoming-teardown.log')).write_bytes(stdout + stderr)
            assert server.returncode == 2 and b'AUTH_OK' in stdout, (stdout, stderr) # Idle peers never complete application work.
        finally:
            # Cleanup remains bounded even if a telemetry identity or lifecycle assertion fails.
            stop(server)
            for child in children:
                stop(child)
    return dict(passed=True, closes=len(closes), identities=len(successes), remote_loss=remote_loss)


# Collect a small complete exporter lifetime after its bounded peer exits; no collector worker is needed.
def completed_capture(server):
    connection, _ = server.accept()
    with connection:
        connection.settimeout(5)
        hello = frame(connection)
        events = []
        # The bounded mesh schedules emit far fewer than 128 frames; enforce the harness storage limit.
        while connection.recv(1, socket.MSG_PEEK):
            assert len(events) < 128, 'unbounded mesh telemetry'
            events.append(frame(connection))
        return hello, events


# Real retained engines share one registration/ID sequence through fallback, duplicate closes and reconnects.
def mesh_lifetimes(binary, certificates, chain, folder, bad_pin=False):
    from test_quic_mesh import pairing, preferred
    with listener() as a, listener(ipv6=True) as b:
        controls = dict(chain=chain, a=f'127.0.0.1:{a.getsockname()[1]}',
                        b=f'[::1]:{b.getsockname()[1]}')
        result = pairing(('nim', 'nim'), certificates, 1 if bad_pin else 8, 0,
                         bad_pin=bad_pin, binaries={'nim': binary}, directory=folder, telemetry=controls)
        identities = {role: (certificates/f'{role}.pub').read_bytes() for role in ('a', 'b')}
        observations = {}
        # Each exporter owns exactly one TCP stream despite retaining two QUIC transports.
        for role, collector in (('a', a), ('b', b)):
            hello, events = completed_capture(collector)
            other = 'b' if role == 'a' else 'a'
            assert hello[0] == 1 and hello[155:187] == identities[role]
            assert hello[187:203] == socket.inet_pton(socket.AF_INET6, '::1')
            if not bad_pin:
                # Registration advertises the listener, never the ephemeral outgoing socket.
                assert int.from_bytes(hello[203:205], 'little') == result['listener_ports'][role]
            starts, outcomes, statuses, closed = {}, {}, [], 0
            # Every frame consumes one ID here: small loopback captures must not contain loss markers.
            for event_id, event in enumerate(events):
                tag = event[8]
                assert tag in (10, 21, 22, 23, 24, 25, 26, 27), tag
                if tag == 10:
                    statuses.append(int.from_bytes(event[9:13], 'little'))
                elif tag in (21, 24):
                    starts[event_id] = tag
                    if tag == 24:
                        # A wrong-pin test deliberately dials c's identity while contacting b's listener.
                        expected = (certificates/'c.pub').read_bytes() if bad_pin and role == 'a' else identities[other]
                        assert event[9:41] == expected
                        assert event[41:57] == socket.inet_pton(socket.AF_INET6, '::1')
                    else:
                        assert event[9:25] == socket.inet_pton(socket.AF_INET6, '::1')
                elif tag in (22, 23, 25, 26):
                    attempt = int.from_bytes(event[9:17], 'little')
                    assert attempt in starts and attempt not in outcomes and attempt < event_id
                    assert starts[attempt] == (21 if tag in (22, 23) else 24)
                    outcomes[attempt] = tag
                    if tag == 23:
                        assert event[17:] == identities[other]
                else:
                    # Each actual duplicate or retained connection close carries the authenticated remote key.
                    assert event[9:41] == identities[other] and event[41:] == b'\0\0'
                    closed += 1
            assert starts.keys() == outcomes.keys(), (starts, outcomes)
            assert set(statuses) <= {0, 1}, statuses
            if bad_pin:
                # The rejecting peer must never report authentication or disconnection for the wrong identity.
                if role == 'a':
                    assert set(outcomes.values()) <= {22, 25} and 25 in outcomes.values() and closed == 0
            else:
                # One fallback and seven duplicate races give fifteen authenticated connections per node.
                assert len(starts) == 15 and closed == 15 and set(outcomes.values()) == {23, 26}
                expected_out = 7 if preferred(identities[role], identities[other]) else 8
                assert list(starts.values()).count(24) == expected_out
                assert set(statuses) == {0, 1}, statuses
            observations[role] = dict(attempts=len(starts), closures=closed, statuses=statuses)
            collector.settimeout(0.1)
            try:
                extra, _ = collector.accept()
                extra.close()
                raise AssertionError('mesh opened more than one exporter stream')
            except socket.timeout:
                pass # No reconnect was induced; one registration per node is required.
        return dict(passed=True, bad_pin=bad_pin, observations=observations)


# Exercise timeout teardown with either an unanswered dial or one authenticated connection still retained.
def mesh_shutdown(binary, certificates, chain, folder, silent=False):
    from test_quic_mesh import ports, observe
    folder.mkdir(parents=True, exist_ok=True)
    gate = folder/f'gate-{time.time_ns()}'
    gate.mkdir()
    (gate/'start-0').touch()
    local_ports = ports()
    processes, handles, logs = {}, {}, {}
    with listener() as collector, socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as sink:
        # Keep the silent UDP destination bound so no ICMP refusal can replace a pending handshake.
        sink.bind(('::1', 0))
        roles = ('a',) if silent else ('a', 'b')
        try:
            # Both retained transports share each process's single exporter; only a is captured here.
            for index, role in enumerate(roles):
                other = 'b' if role == 'a' else 'a'
                remote_port = sink.getsockname()[1] if silent else local_ports[1-index]
                logs[role] = folder/f'{role}.log'
                handles[role] = logs[role].open('w')
                command = [str(binary), 'mesh', str(local_ports[index]), str(remote_port),
                           str(certificates/f'{role}.cert.pem'), str(certificates/f'{role}.key.pem'),
                           str(certificates/f'{role}.pub'), str(certificates/f'{other}.pub'),
                           'jamnp-s/1/245becfe', str(gate)]
                if role == 'a':
                    command += ['--chain', str(chain), '--telemetry', f'127.0.0.1:{collector.getsockname()[1]}']
                processes[role] = subprocess.Popen(command, stdout=handles[role], stderr=subprocess.STDOUT,
                    env={**os.environ, 'RAGNAROK_MESH_ROUNDS': '1', 'RAGNAROK_MESH_FALLBACK': '0',
                         'RAGNAROK_MESH_DISRUPT': '0'})
            if not silent:
                # Leave the close gate absent after healthy exchange; both owners time out with a live peer.
                observe(processes, logs, 'MESH_EXCHANGED 0 8', {role: {} for role in roles})
            for role, process in processes.items():
                assert process.wait(timeout=20) == 2, logs[role].read_text()
            hello, events = completed_capture(collector)
            assert hello[155:187] == (certificates/'a.pub').read_bytes()
            starts, outcomes, closures = {}, {}, 0
            # Status frames consume IDs too; correlate using positions in this complete capture.
            for event_id, event in enumerate(events):
                tag = event[8]
                assert tag in (10, 21, 22, 23, 24, 25, 26, 27), tag
                if tag in (21, 24):
                    starts[event_id] = tag
                elif tag in (22, 23, 25, 26):
                    attempt = int.from_bytes(event[9:17], 'little')
                    assert attempt in starts and attempt not in outcomes and attempt < event_id
                    assert starts[attempt] == (21 if tag in (22, 23) else 24)
                    outcomes[attempt] = tag
                elif tag == 27:
                    assert event[9:41] == (certificates/'b.pub').read_bytes()
                    closures += 1
            assert starts.keys() == outcomes.keys(), (starts, outcomes)
            if silent:
                assert list(starts.values()) == [24] and list(outcomes.values()) == [25] and closures == 0
            else:
                # The discarded duplicate really closes; destroying the retained connection adds no second close.
                assert len(starts) == 2 and set(outcomes.values()) == {23, 26} and closures == 1
            return dict(passed=True, silent=silent, attempts=len(starts), closures=closures)
        finally:
            # Failed collector assertions must not leave either QUIC process or diagnostic file behind.
            for process in processes.values():
                stop(process)
            for handle in handles.values():
                handle.close()

