"""Bounded real TCP collector tests, including actual proof-peer CLI registration."""
from pathlib import Path
import hashlib
import json
import os
import socket
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
                status = frame(first)
                assert len(status) == 43 and status[8] == 10
                assert struct.unpack_from('<I', status, 9)[0] == 7
                # RST exercises SIGPIPE/error isolation and retry timing on both supported hosts.
                first.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
            second, _ = server.accept()
            with second:
                second.settimeout(5)
                assert frame(second) == hello
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
    environment = dict(os.environ, RAGNAROK_TELEMETRY_CHAIN=str(chain))
    alpn = 'jamnp-s/1/' + genesis.hex()[:8]
    with listener() as server:
        endpoint = f'127.0.0.1:{server.getsockname()[1]}'
        args = [str(binary), 'server', str(port), str(certificates/'a.cert.pem'),
                str(certificates/'a.key.pem'), str(certificates/'b.pub'), alpn, '7000',
                '--telemetry', endpoint]
        process = subprocess.Popen(args, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
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
                    str(certificates/'a.pub'), alpn, '3000'], capture_output=True, timeout=6)
                assert client.returncode == 0, (client.stdout, client.stderr)
            stdout, stderr = process.communicate(timeout=5)
            (folder/'peer.log').write_bytes(stdout + stderr)
            assert process.returncode == 0 and b'EXCHANGE_OK 8' in stdout, (stdout, stderr)
        finally:
            # A failed handshake must not leave the UDP listener or TCP exporter behind.
            stop(process)
    return dict(passed=True, genesis=genesis.hex(), identity='local certificate', peers_before_connect=0)
