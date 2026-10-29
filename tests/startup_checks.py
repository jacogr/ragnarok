# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Real default startup, stable TLS identity, selected storage and graceful listener lifetimes.

The run entry point owns build-directory inputs and subprocesses; it never mutates tracked fixtures.
"""
import gzip
import hashlib
import json
import os
import signal
import socket
import stat
import subprocess
import time
import tempfile
from pathlib import Path
from urllib.request import Request, urlopen


def run(binary, folder):
    """Exercise omitted settings and explicit overrides against the checked production executable."""
    root = Path(__file__).resolve().parents[1]
    folder = Path(folder).resolve()/('run-'+str(time.time_ns()))
    folder.mkdir(parents=True)
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(('JAM_FUZZ', 'RAGNAROK_'))}
    results = []

    def port():
        """Select an explicit override; the bare case independently checks port 34100."""
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
            reservation.bind(('127.0.0.1', 0))
            return str(reservation.getsockname()[1])

    def start(directory, arguments):
        """Reap startup refusals and retain their diagnostic output."""
        directory.mkdir(parents=True, exist_ok=True)
        log = directory/'process.log'
        output = log.open('w')
        process = None
        try:
            process = subprocess.Popen([str(binary), 'server', *arguments], cwd=directory,
                                       env=environment, stdout=output, stderr=subprocess.STDOUT)
            deadline = time.monotonic()+15
            while 'READY' not in log.read_text().splitlines():
                # Readiness requires the actual endpoint; a timeout or early exit is a failure.
                assert process.poll() is None, log.read_text()
                assert time.monotonic() < deadline, log.read_text()
                time.sleep(0.02)
            return process, output, log
        except BaseException:
            # Failed launches and interrupted tests must still retire the child and diagnostic stream.
            if process is not None:
                if process.poll() is None:
                    process.kill()
                process.wait()
            output.close()
            raise

    def stop(process, output, log):
        """SIGTERM must return through ordinary native cleanup with exit status zero."""
        try:
            process.send_signal(signal.SIGTERM)
            assert process.wait(timeout=10) == 0, log.read_text()
        finally:
            # Preserve the failure verdict while reaping even an unresponsive child.
            if process.poll() is None:
                process.kill()
                process.wait()
            output.close()

    # Help and syntactically invalid credentials never create a default identity.
    clean = folder/'inspection'
    clean.mkdir()
    for arguments in [['server', '--help'], ['server', '--net-cert', 'only.pem'],
                      ['server', '--unknown']]:
        result = subprocess.run([str(binary), *arguments], cwd=clean, env=environment,
                                capture_output=True, text=True, timeout=5)
        assert result.returncode == (0 if '--help' in arguments else 2), result
        assert list(clean.iterdir()) == [], list(clean.iterdir())
    results.append('help and invalid CLI have no filesystem effects')

    # UI implies RPC; independently enabling MCP must preserve three distinct default listeners.
    process, output, log = start(folder/'ui-defaults', ['--with-ui', '--with-mcp', '--net-port', port()])
    try:
        with urlopen(Request('http://127.0.0.1:8418/', headers={'Accept-Encoding': 'gzip'}), timeout=5) as response:
            assert response.status == 200 and b'id="endpoint"' in gzip.decompress(response.read())
        with socket.create_connection(('127.0.0.1', 9418), timeout=5):
            pass # The existing RPC/browser workload owns the WebSocket protocol assertions.
        with socket.create_connection(('127.0.0.1', 14141), timeout=5):
            pass # MCP lifecycle/query semantics remain covered by its owning E2E workload.
    finally:
        stop(process, output, log)
    service_log = log.read_text()
    for message in ['UI listening on http://127.0.0.1:8418/', 'RPC listening on ws://127.0.0.1:9418/',
                    'MCP listening on http://127.0.0.1:14141/mcp', 'Stopping UI listener',
                    'Stopping RPC listener', 'Stopping MCP listener']:
        assert message in service_log, service_log
    # Recently closed HTTP/RPC clients must not prevent an immediate foreground restart.
    process, output, log = start(folder/'ui-defaults', ['--with-ui', '--with-mcp', '--net-port', port()])
    stop(process, output, log)
    results.append('UI, implicit RPC and MCP listen on ports 8418, 9418 and 14141')

    # A missing collector is isolated from networking and reconnects on the bounded retry.
    with tempfile.TemporaryDirectory(prefix='ragnarok-log-', dir='/tmp') as management, socket.socket() as collector:
        collector.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        collector.bind(('127.0.0.1', 0))
        management_socket = str(Path(management)/'control.sock')
        endpoint = '127.0.0.1:'+str(collector.getsockname()[1])
        process, output, log = start(folder/'telemetry', [
            '--net-port', port(), '--chain', str(root/'tests/fixtures/telemetry-dev.json'),
            '--with-telemetry', '--telemetry-endpoint', endpoint,
            '--with-management', '--management-socket', management_socket])
        try:
            deadline = time.monotonic()+10
            while 'Telemetry collector connection unavailable; retrying in 5s' not in log.read_text():
                assert process.poll() is None and time.monotonic() < deadline, log.read_text()
                time.sleep(0.02)
            collector.listen(1)
            collector.settimeout(10)
            connection, _ = collector.accept()
            with connection:
                connection.settimeout(5)
                assert connection.recv(2048), log.read_text()
                deadline = time.monotonic()+5
                while 'Connected to telemetry collector' not in log.read_text():
                    assert process.poll() is None and time.monotonic() < deadline, log.read_text()
                    time.sleep(0.02)
        finally:
            stop(process, output, log)
        service_log = log.read_text()
        assert 'Telemetry destination: '+endpoint in service_log, service_log
        assert 'Stopping telemetry exporter' in service_log, service_log
        assert 'Management listening on '+management_socket in service_log, service_log
        assert 'Stopping management listener' in service_log, service_log
    results.append('telemetry reports endpoint, refusal, bounded retry, connection and shutdown')

    # Successive real clients prove the default server outlives a bounded eight-request workload.
    directory = folder/'bare'
    process, output, log = start(directory, [])
    try:
        identity = directory/'data/network'
        files = {name: (identity/name).read_bytes()
                 for name in ['key.pem', 'cert.pem', 'public.key']}
        assert len(files['public.key']) == 32
        assert stat.S_IMODE((identity/'key.pem').stat().st_mode) == 0o600
        for _ in range(2):
            client = subprocess.run([str(binary), 'client', '--net-peer-key',
                                     str(identity/'public.key'), '--net-timeout-ms', '3000'],
                                    cwd=directory, env=environment, capture_output=True,
                                    text=True, timeout=10)
            assert client.returncode == 0 and 'EXCHANGE_OK 8' in client.stdout, client
            assert process.poll() is None, log.read_text()
    finally:
        stop(process, output, log)
    process, output, log = start(directory, [])
    try:
        assert all((identity/name).read_bytes() == data for name, data in files.items())
    finally:
        stop(process, output, log)
    results.append('bare UDP 34100 server, two pinned clients, graceful stop and stable restart')

    # Untrusted stream failures must not terminate a persistent listener or poison later clients.
    isolated = folder/'stream-isolation'
    selected = port()
    process, output, log = start(isolated, ['--net-port', selected])
    base = [str(binary), 'client', '--net-port', selected, '--net-peer-key',
            str(isolated/'data/network/public.key'), '--net-timeout-ms', '2000']
    try:
        for mode in ['bad-kind', 'oversize', 'unknown', 'truncated', 'trailing', 'no-fin']:
            before = log.read_text().count('Request rejected: timed out before FIN')
            rejected = subprocess.run([*base, '--net-mode', mode], cwd=isolated,
                                      env=environment, capture_output=True, text=True, timeout=10)
            assert rejected.returncode == 2 and 'AUTH_OK' in rejected.stdout, rejected
            assert process.poll() is None, log.read_text()
            if mode == 'no-fin':
                assert log.read_text().count('Request rejected: timed out before FIN') > before, log.read_text()
            healthy = subprocess.run(base, cwd=isolated, env=environment,
                                     capture_output=True, text=True, timeout=10)
            assert healthy.returncode == 0 and 'EXCHANGE_OK 8' in healthy.stdout, healthy
        # The standalone cancellation workload resets paused reads through the real transport.
        cancelled = subprocess.run([*base, '--net-mode', 'cancel'], cwd=isolated,
                                   env=environment, capture_output=True, text=True, timeout=10)
        assert cancelled.returncode == 0 and 'CANCEL_OK' in cancelled.stdout, cancelled
        assert process.poll() is None, log.read_text()
        healthy = subprocess.run(base, cwd=isolated, env=environment,
                                 capture_output=True, text=True, timeout=10)
        assert healthy.returncode == 0 and 'EXCHANGE_OK 8' in healthy.stdout, healthy
    finally:
        stop(process, output, log)
    results.append('malformed, timed-out and cancelled streams preserve later healthy exchanges')

    # Explicit locations replace defaults without creating the unused default root.
    custom = folder/'custom'
    process, output, log = start(custom, ['--data-dir', 'owned', '--net-port', port()])
    try:
        assert (custom/'owned/network/key.pem').exists() and not (custom/'data').exists()
    finally:
        stop(process, output, log)
    results.append('explicit data root and network port')

    # A caller-selected finite deadline is a successful listener shutdown too.
    finite = folder/'deadline'
    finite.mkdir()
    result = subprocess.run([str(binary), 'server', '--net-port', port(),
                             '--net-timeout-ms', '150'], cwd=finite, env=environment,
                            capture_output=True, text=True, timeout=10)
    assert result.returncode == 0 and 'READY' in result.stdout.splitlines(), result
    results.append('finite listener deadline')

    # Normal output must show runtime identity, honest unknown sync state and joined shutdown.
    logged = folder/'logging'
    logged.mkdir()
    result = subprocess.run([str(binary), 'server', '--net-port', port(),
                             '--net-timeout-ms', '5600'], cwd=logged, env=environment,
                            capture_output=True, text=True, timeout=15)
    (logged/'node.log').write_text(result.stderr)
    assert result.returncode == 0, result
    for message in ['Ragnarok ', 'Platform:', 'Role: FULL; block production: disabled',
                    'Local node identity:', 'JAMNP-S over QUIC', 'Waiting for peers',
                    'sync target: unknown', 'Stopping peer networking', 'Shutdown complete']:
        assert message in result.stderr, (message, result.stderr)
    assert 'Idle' not in result.stderr and 'Caught up' not in result.stderr, result.stderr
    for line in result.stderr.splitlines():
        assert len(line) > 21 and line[4] == '-' and line[19:21] == 'Z ', line
    for level in ['warn', 'off']:
        quiet = subprocess.run([str(binary), 'server', '--net-port', port(),
                                '--net-timeout-ms', '100', '--log-level', level], cwd=logged,
                               env=environment, capture_output=True, text=True, timeout=10)
        assert quiet.returncode == 0 and quiet.stderr == '', quiet
    # Warning verbosity must retain a real rejection without Info/Debug chatter.
    warning_port = port()
    warning_dir = folder/'warning-rejection'
    process, output, log = start(warning_dir, ['--net-port', warning_port, '--log-level', 'warn'])
    try:
        invalid = subprocess.run([str(binary), 'client', '--net-port', warning_port,
                                  '--net-peer-key', str(warning_dir/'data/network/public.key'),
                                  '--net-mode', 'bad-kind', '--net-timeout-ms', '2000'],
                                 cwd=warning_dir, env=environment, capture_output=True,
                                 text=True, timeout=10)
        assert invalid.returncode == 2, invalid
    finally:
        stop(process, output, log)
    messages = log.read_text()
    assert '[warn][network]' in messages and '[info]' not in messages and '[debug]' not in messages, messages
    results.append('timestamped node identity, periodic sync status, shutdown and quiet levels')

    # Each real layout owner must create and reopen its own inferred namespace.
    fixture = root/'tests/fixtures/rpc-genesis.json'
    digest = hashlib.sha256(fixture.read_bytes()).digest()
    for layout, child in [('journal', 'state.db'), ('managed', 'managed'), ('paged', 'paged')]:
        case = folder/('disk-'+layout)
        case.mkdir()
        (case/'chain.json').write_bytes(fixture.read_bytes())
        arguments = ['--net-port', port(), '--with-state', '--state-storage', 'disk',
                     '--state-layout', layout]
        for _ in range(2):
            process, output, log = start(case, arguments)
            try:
                assert (case/'data/full'/child).exists(), list((case/'data/full').iterdir())
            finally:
                stop(process, output, log)
        results.append('default '+layout+' database creation and restart')
    assert hashlib.sha256(fixture.read_bytes()).digest() == digest, 'Tracked fixture changed'

    # Partial publication must refuse without rotating the already selected private key.
    (identity/'cert.pem').unlink()
    result = subprocess.run([str(binary), 'server'], cwd=directory, env=environment,
                            capture_output=True, text=True, timeout=5)
    assert result.returncode == 2 and 'Incomplete or unsafe TLS identity' in result.stderr, result
    assert (identity/'key.pem').read_bytes() == files['key.pem']
    results.append('partial identity refuses without key rotation')
    (folder/'results.json').write_text(json.dumps({'passed': True, 'checks': results}, indent=2)+'\n')
    return {'passed': True, 'checks': results}
