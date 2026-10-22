# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Observe actual current-command exits and progress alongside an independent native TLS/map witness.

Exposes observe; process failures always reap the responder and cannot borrow another case's verdict.
"""
import subprocess
import tempfile
import time
from pathlib import Path


def ready_port(process, folder, seconds=20):
    """Wait for a live witness and a complete bounded port without guessing partial readiness."""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise ValueError('Current download witness exited before readiness: '+str(folder))
        path = folder/'current-ready'
        if path.exists():
            text = path.read_text()
            if text.isascii() and text.isdecimal() and 1 <= int(text) <= 65535:
                return int(text)
        time.sleep(0.01)
    raise ValueError('Current download witness readiness deadline: '+str(folder))


def observe(peer, responder, directory, environment):
    """Check each current command transcript and independent durable prefix before the next case."""
    directory.mkdir(parents=True, exist_ok=True)
    cases = [('journal', 0, 1, 1, 'ADOPTED', 1), ('managed', 0, 1, 1, 'ADOPTED', 1),
             ('replay', 2, 2, 1, 'FAILED Exhausted', 2),
             ('empty', 2, 2, 1, 'FAILED Exhausted', 2),
             ('timeout', 2, 2, 1, 'FAILED Timeout', 2),
             ('legacy-policy', 2, 1, 0, 'FAILED InvalidPolicy', 0)]
    rows = []
    for name, expected_code, requested, adopted, marker, requests in cases:
        folder = Path(tempfile.mkdtemp(prefix=name+'-', dir=directory))
        log = folder/'responder.log'
        process = None
        try:
            with log.open('w') as output:
                process = subprocess.Popen([str(responder)], cwd=folder,
                    env=dict(environment, RAGNAROK_CURRENT_DOWNLOAD_CASE=name),
                    stdout=output, stderr=subprocess.STDOUT)
                port = ready_port(process, folder)
                arguments = [str(peer), 'download-current', str(port),
                    environment['RAGNAROK_TEST_CERT'], environment['RAGNAROK_TEST_KEY'],
                    environment['RAGNAROK_TEST_PEER_B'], 'jamnp-s/1/00000000',
                    '4000' if name == 'timeout' else '10000', 'current-policy.conf',
                    '--with-state', '--chain', 'current-chain.json', '--state-writes', '1000',
                    '--state-write-bytes', '1000000', '--state-storage', 'disk',
                    '--state-db', 'current-state.db', '--download-blocks', str(requested)]
                if name in ('managed', 'empty'):
                    arguments += ['--state-layout', 'managed', '--state-compact-bytes', '0']
                result = subprocess.run(arguments, cwd=folder, env=environment,
                    capture_output=True, text=True, timeout=20)
                (folder/'application.stdout').write_text(result.stdout)
                (folder/'application.stderr').write_text(result.stderr)
                (folder/'current-stop').write_text('stop')
                code = process.wait(timeout=10)
            # Exact standalone markers prevent stale/partial output from supplying a success verdict.
            progress = f'CURRENT_DOWNLOAD_PROGRESS adopted={adopted} requested={requested}'
            verified = f'CURRENT_EXECUTABLE_VERIFIED adopted={adopted} requests={requests}'
            passed = (result.returncode == expected_code and code == 0
                      and 'CURRENT_DOWNLOAD_'+marker in (result.stdout+result.stderr).splitlines()
                      and (requested == 1 or progress in result.stdout.splitlines())
                      and verified in log.read_text().splitlines())
            row = dict(case=name, command=arguments, exit_code=result.returncode,
                responder_exit_code=code, stdout=str(folder/'application.stdout'),
                stderr=str(folder/'application.stderr'), responder_log=str(log), passed=passed)
            rows.append(row)
            if not passed:
                raise ValueError('Executable current download verification failed: '+str(row))
        finally:
            if process is not None and process.poll() is None:
                # Reap every native listener/callback owner even if readiness or the command times out.
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
    return dict(passed=len(rows) == len(cases) and all(row['passed'] for row in rows), cases=rows)
