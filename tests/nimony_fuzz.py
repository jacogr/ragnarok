# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exercise the real fuzz entry point with existing independently calculated current STF traces.

These fixed adapter checks generate no random campaigns and do not substitute for polkajam-fuzz.
"""
import hashlib
import os
from pathlib import Path
import signal
import socket
import struct
import subprocess
import tempfile
import time


def exact(peer, size):
    """Require a whole bounded response; EOF and partial-prefix success are forbidden."""
    data = b''
    while len(data) < size:
        chunk = peer.recv(size-len(data))
        assert chunk, 'unexpected EOF during fuzzer response'
        data += chunk
    return data


def exchange(peer, payload):
    """Send the pinned E4 length framing and require a complete bounded response."""
    peer.sendall(struct.pack('<I', len(payload))+payload)
    size = struct.unpack('<I', exact(peer, 4))[0]
    assert 0 < size <= 16777216
    return exact(peer, size)


def connect(path):
    """A fresh real client always performs protocol1/current-profile handshake first."""
    peer = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    peer.settimeout(10)
    try:
        peer.connect(str(path))
        response = exchange(peer, bytes([0, 1])+bytes(4)+bytes([0, 8, 0])+bytes(3)+b'\x04test')
        assert response[0:2] == bytes([0, 1]) and response[2:6] == bytes(4)
        assert response[6:9] == bytes([0, 8, 0])
        return peer
    except BaseException:
        # Failed handshakes never leak a test-owned descriptor.
        peer.close()
        raise


def exercise(binary, policy_binary, folder):
    """Compare an actual socket successor and complete maps with an existing frozen independent trace."""
    from current_stf_trace_command_oracle import expected_observations
    from state_layout_oracle import digest
    import state_trace_wire_oracle as raw
    import block_oracle
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for path, sha in FIXTURE_CONTRACTS['current_stf_trace_command'][2]:
        # Provenance and independently authored expectations precede native process execution.
        assert hashlib.sha256(path.read_bytes()).hexdigest() == sha
    jobs, _, _ = expected_observations()
    job = jobs[0]
    genesis = job['genesis']
    before, consumed = raw.prefix(genesis[297:])
    assert 297+consumed == len(genesis)
    original, prefix = raw.prefix(job['steps'][0])
    length, _, _ = block_oracle.parse('B', job['steps'][0][prefix:], block_oracle.TINY)
    body = job['steps'][0][prefix:prefix+length]
    after, count = raw.prefix(job['steps'][0][prefix+length:])
    assert prefix+length+count == len(job['steps'][0]) and original == before
    initialize = b'\x01'+genesis[:297]+genesis[329:]+b'\x00'
    original_state = b'\x05'+raw.wire(before)[32:]
    successor_state = b'\x05'+raw.wire(after)[32:]
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    log_path = folder/'jam-fuzzer-target-process.log'
    with tempfile.TemporaryDirectory(prefix='ragnarok-fuzz-') as selected:
        directory = Path(selected)
        directory.chmod(0o700)
        endpoint = directory/'target.sock'
        assert len(str(endpoint).encode()) <= 103
        policy = directory/'policy.txt'
        parameters = directory/'parameters.json'
        subprocess.run([str(policy_binary), str(policy)], check=True, timeout=30)
        parameters.write_text(job['config'])
        arguments = [str(binary), 'serve-fuzz', str(policy), str(parameters), '1000', '1000000']
        environment = {k:v for k,v in os.environ.items() if not k.startswith('JAM_FUZZ')}
        environment.update(JAM_FUZZ='1', JAM_FUZZ_SPEC='tiny', JAM_FUZZ_DATA_PATH=str(directory),
                           JAM_FUZZ_SOCK_PATH=str(endpoint), JAM_FUZZ_LOG_LEVEL='error')
        missing = []
        for variable in ('JAM_FUZZ_SPEC', 'JAM_FUZZ_DATA_PATH', 'JAM_FUZZ_SOCK_PATH'):
            # Missing mandatory configuration must refuse startup before opening a listener.
            refused = dict(environment)
            del refused[variable]
            result = subprocess.run(arguments, env=refused, capture_output=True, timeout=30)
            assert result.returncode == 2 and b'FUZZ_START_FAILED' in result.stderr
            assert not endpoint.exists()
            missing.append(variable)
        with log_path.open('wb') as log:
            process = subprocess.Popen(arguments, env=environment, stdout=log, stderr=log)
            try:
                deadline = time.monotonic()+30
                while not endpoint.exists():
                    assert process.poll() is None, log_path.read_text(errors='replace')[-2000:]
                    assert time.monotonic() < deadline, 'fuzz listener startup deadline'
                    time.sleep(0.01)
                with connect(endpoint) as peer:
                    assert exchange(peer, initialize) == b'\x02'+genesis[297:329]
                    assert exchange(peer, b'\x04'+digest(genesis[:297])) == original_state
                    bad = bytearray(body)
                    bad[32] ^= 1
                    assert exchange(peer, b'\x03'+bad)[0] == 255
                    assert exchange(peer, b'\x04'+digest(genesis[:297])) == original_state
                    assert exchange(peer, b'\x03'+body) == b'\x02'+raw.wire(after)[:32]
                    assert exchange(peer, b'\x04'+digest(body[:297])) == successor_state
                with connect(endpoint) as peer:
                    # Reconnection starts with no imported child history, even for the same seed hash.
                    assert exchange(peer, initialize) == b'\x02'+genesis[297:329]
                    payload = b'\x04'+digest(body[:297])
                    peer.sendall(struct.pack('<I', len(payload))+payload)
                    assert peer.recv(1) == b''
                process.send_signal(signal.SIGTERM)
                assert process.wait(timeout=30) == 0
                assert not endpoint.exists(), 'normal shutdown must remove its owned socket'
            finally:
                # Every assertion/timeout retires the exact process, never a broad process-name match.
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=10)
        assert parameters.read_text() == job['config']
    return dict(passed=True, missing_environment=missing, signed_imports=1,
                consensus_rejections=1, complete_state_queries=3, reconnects=1,
                log=str(log_path), scope='fixed independent current-profile socket adapter checks; no generated campaign')
