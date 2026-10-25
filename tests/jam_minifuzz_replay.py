# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Strict bounded observation around the unmodified upstream minifuzz process and actual target socket."""
import hashlib
import json
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
from jam_minifuzz_trace import write_trace


def exact(peer, size):
    """A truncated frame is failure; no short read or EOF can become a completed exchange."""
    result = bytearray()
    while len(result) < size:
        chunk = peer.recv(size-len(result))
        if not chunk:
            raise ValueError('Incomplete minifuzz frame')
        result.extend(chunk)
    return bytes(result)


def receive(peer):
    """Check the pinned E4 message extent before allocation or reading the body."""
    size = struct.unpack('<I', exact(peer, 4))[0]
    if not 0 < size <= 16777216:
        raise ValueError('Invalid minifuzz message extent')
    return exact(peer, size)


def send(peer, data):
    """Write one complete bounded canonical frame without changing its payload."""
    if not 0 < len(data) <= 16777216:
        raise ValueError('Invalid minifuzz outgoing extent')
    peer.sendall(struct.pack('<I', len(data))+data)


def replay(script, environment, endpoint, folder, pairs, *, corrupt_last=False, spec='tiny'):
    """Require every actual exchange and process completion; upstream exit0 alone never proves success."""
    if spec not in ('tiny', 'full'):
        raise ValueError('Unknown minifuzz profile')
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    trace = folder/'trace'
    files = write_trace(trace, pairs)
    observed = []
    failure = None
    code = None
    process = None
    with tempfile.TemporaryDirectory(prefix='jam-minifuzz-') as selected:
        proxy = Path(selected)/'proxy.sock'
        assert len(str(proxy).encode()) <= 103
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener, (folder/'upstream.log').open('wb') as log:
            listener.bind(str(proxy))
            listener.listen(1)
            listener.settimeout(30)
            try:
                process = subprocess.Popen([sys.executable, '-S', str(script), '--spec', spec,
                    '--trace-dir', str(trace.resolve()), '--target-sock', str(proxy), '--stop-after', str(len(pairs))],
                    env=environment, stdout=log, stderr=log)
                client, _ = listener.accept()
                with client, socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as target:
                    client.settimeout(30)
                    target.settimeout(30)
                    target.connect(str(endpoint))
                    for index, (request, expected) in enumerate(pairs):
                        actual_request = receive(client)
                        if actual_request != request:
                            raise ValueError('Minifuzz request differs from independently prepared bytes')
                        send(target, actual_request)
                        actual_reply = receive(target)
                        if corrupt_last and index == len(pairs)-1:
                            damaged = bytearray(actual_reply)
                            damaged[-1] ^= 1
                            actual_reply = bytes(damaged) # Explicit test-only false-success witness; target execution remains unchanged.
                        observed.append(dict(request_sha256=hashlib.sha256(actual_request).hexdigest(),
                                             reply_sha256=hashlib.sha256(actual_reply).hexdigest()))
                        if actual_reply != expected:
                            failure = 'Unexpected target response at exchange '+str(index)
                        send(client, actual_reply)
                        if failure is not None:
                            break # Let the real upstream comparison observe the wrong reply and its own exit status.
                    if client.recv(1) != b'':
                        raise ValueError('Unexpected extra minifuzz request')
                code = process.wait(timeout=30)
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                failure = str(error)
            finally:
                if process is not None and process.poll() is None:
                    process.kill()
                    process.wait(timeout=10) # Every timeout/error retires only this owned process.
                if process is not None:
                    code = process.returncode
    result = dict(passed=failure is None and code == 0 and len(observed) == len(pairs),
                  planned_exchanges=len(pairs), completed_exchanges=len(observed),
                  upstream_exit_code=code, failure=failure, files=files, observed=observed)
    (folder/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    return result
