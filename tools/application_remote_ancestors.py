# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Observe real executable remote-ancestor commands against independent native TLS/maps.

Exposes observe; native code owns protocol/complete-state assertions, Python owns process/CLI/cleanup.
"""
import subprocess
import tempfile
from pathlib import Path
from application_download_sequence import ready_port


def observe(peer, responder, directory, environment):
    """Retain per-case process evidence and reap the independent witness on every failure path."""
    directory.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, code, adopted, marker, requests in (
        ('complete', 0, 1, 'DOWNLOAD_ADOPTED', 2),
        ('managed', 0, 1, 'DOWNLOAD_ADOPTED', 2),
        ('wrong-parent', 2, 0, 'DOWNLOAD_FAILED Exhausted', 1),
        ('timeout', 2, 0, 'DOWNLOAD_FAILED Timeout', 1),
    ):
        folder = Path(tempfile.mkdtemp(prefix=name+'-', dir=directory))
        log = folder/'responder.log'
        process = None
        try:
            # Fixture readiness is validated by the existing bounded process helper.
            with log.open('w') as output:
                process = subprocess.Popen([str(responder)], cwd=folder,
                    env=dict(environment, RAGNAROK_REMOTE_ANCESTOR_CASE=name),
                    stdout=output, stderr=subprocess.STDOUT)
                port = ready_port(process, folder)
                arguments = [str(peer), 'download', str(port), environment['RAGNAROK_TEST_CERT'],
                    environment['RAGNAROK_TEST_KEY'], environment['RAGNAROK_TEST_PEER_B'],
                    'jamnp-s/1/00000000', '1000' if name == 'timeout' else '10000',
                    'sequence-policy.conf', '--with-state', '--chain', 'sequence-chain.json',
                    '--state-writes', '1000', '--state-write-bytes', '1000000',
                    '--state-storage', 'disk', '--state-db', 'sequence-state.db',
                    '--download-remote-ancestors', '1']
                if name == 'managed':
                    # The same canonical expectation covers the explicit managed disk layout.
                    arguments += ['--state-layout', 'managed']
                result = subprocess.run(arguments, cwd=folder, env=environment,
                    text=True, capture_output=True, timeout=20)
                (folder/'application.stdout').write_text(result.stdout)
                (folder/'application.stderr').write_text(result.stderr)
                (folder/'sequence-stop').write_text('stop')
                witness_code = process.wait(timeout=10)
            combined = result.stdout+result.stderr
            verified = f'REMOTE_ANCESTORS_VERIFIED adopted={adopted} requests={requests}'
            passed = (result.returncode == code and marker in combined
                and witness_code == 0 and verified in log.read_text())
            row = dict(case=name, command=arguments, exit_code=result.returncode,
                responder_exit_code=witness_code, stdout=str(folder/'application.stdout'),
                stderr=str(folder/'application.stderr'), responder_log=str(log), passed=passed)
            rows.append(row)
            if not passed:
                # Preserve exact process paths and verdicts instead of accepting a stale successful binary.
                raise ValueError('Executable remote ancestry verification failed: '+str(row))
        finally:
            if process is not None and process.poll() is None:
                # Every exception/timeout reaps the native responder before another case starts.
                process.kill()
                process.wait()
    return dict(passed=all(row['passed'] for row in rows), cases=rows)
