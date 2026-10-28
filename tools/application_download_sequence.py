# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run real executable multi-block commands against an independent native TLS/map witness.

Exposes observe; Python owns process/CLI assertions and the native responder owns protocol/map checks.
"""
import subprocess
import tempfile
import time
from pathlib import Path


# A partial or stale readiness file cannot launch a command against a guessed endpoint.
def ready_port(process, folder, seconds=20):
    deadline = time.monotonic() + seconds
    path = folder/'sequence-ready'
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise ValueError('Independent sequence responder exited before readiness: '+str(folder))
        if path.exists():
            text = path.read_text()
            if text.isascii() and text.isdecimal() and 1 <= int(text) <= 65535:
                return int(text)
        time.sleep(0.01)
    raise ValueError('Independent sequence responder readiness deadline: '+str(folder))


# Reap the native witness even when startup, timeout, CLI output or protocol evidence fails.
def observe(peer, responder, directory, environment):
    directory.mkdir(parents=True, exist_ok=True)
    rows = []
    cases = [('complete', 0, 3, 'DOWNLOAD_ADOPTED', 3),
             ('resumed', 0, 2, 'DOWNLOAD_ADOPTED', 2),
             ('replay', 2, 1, 'DOWNLOAD_FAILED Exhausted', 2),
             ('timeout', 2, 1, 'DOWNLOAD_FAILED Timeout', 2)]
    for name, expected_code, adopted, marker, requests in cases:
        folder = Path(tempfile.mkdtemp(prefix=name+'-', dir=directory))
        log = folder/'responder.log'
        process = None
        try:
            with log.open('w') as output:
                process = subprocess.Popen([str(responder)], cwd=folder,
                    env=dict(environment, RAGNAROK_DOWNLOAD_SEQUENCE_CASE=name),
                    stdout=output, stderr=subprocess.STDOUT)
                port = ready_port(process, folder)
                arguments = [str(peer), 'download', '--net-port', str(port), '--net-cert', environment['RAGNAROK_TEST_CERT'],
                    '--net-key', environment['RAGNAROK_TEST_KEY'], '--net-peer-key', environment['RAGNAROK_TEST_PEER_B'],
                    '--net-alpn', 'jamnp-s/1/00000000', '--net-timeout-ms', '4000' if name == 'timeout' else '10000',
                    '--download-policy', 'sequence-policy.conf', '--with-state', '--chain', 'sequence-chain.json',
                    '--state-writes', '1000', '--state-write-bytes', '1000000',
                    '--state-storage', 'disk', '--state-db', 'sequence-state.db',
                    '--download-blocks', '2' if name == 'resumed' else '3']
                if name == 'resumed':
                    # The native witness seeded real retained history/finality before advertising readiness.
                    arguments.append('--download-local-ancestors')
                result = subprocess.run(arguments, cwd=folder, env=environment,
                    capture_output=True, text=True, timeout=20)
                (folder/'application.stdout').write_text(result.stdout)
                (folder/'application.stderr').write_text(result.stderr)
                (folder/'sequence-stop').write_text('stop')
                code = process.wait(timeout=10)
            combined = result.stdout + result.stderr
            requested = 2 if name == 'resumed' else 3
            expected_progress = f'DOWNLOAD_PROGRESS adopted={adopted} requested={requested}'
            verified = f'SEQUENCE_VERIFIED adopted={adopted} requests={requests}'
            passed = (result.returncode == expected_code and expected_progress in result.stdout
                      and marker in combined and code == 0 and verified in log.read_text())
            row = dict(case=name, command=arguments, exit_code=result.returncode,
                       responder_exit_code=code, stdout=str(folder/'application.stdout'),
                       stderr=str(folder/'application.stderr'), responder_log=str(log), passed=passed)
            rows.append(row)
            if not passed:
                raise ValueError('Executable sequence verification failed: '+str(row))
        finally:
            if process is not None and process.poll() is None:
                # Every exceptional path ends the independent engine/socket lifetime before the next scenario.
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
    return dict(passed=len(rows) == len(cases) and all(row['passed'] for row in rows), cases=rows)
