# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Observe actual current-command exits and progress alongside an independent native TLS/map witness.

Exposes observe; process failures always reap the responder and cannot borrow another case's verdict.
"""
import subprocess
import tempfile
from pathlib import Path

from application_current_download import ready_port


def observe(peer, responder, directory, environment):
    """Check each current command transcript and independent durable prefix before the next case."""
    directory.mkdir(parents=True, exist_ok=True)
    cases = [('journal', False), ('managed', False), ('journal-resumed', False),
             ('managed-resumed', False), ('replay', True), ('empty', True),
             ('timeout', True), ('resource', True), ('managed-maintenance', False),
             ('maintenance-resource', True), ('maintenance-resumed', False)]
    rows = []
    for name, partial in cases:
        folder = Path(tempfile.mkdtemp(prefix=name+'-', dir=directory))
        log = folder/'responder.log'
        process = None
        try:
            with log.open('w') as output:
                process = subprocess.Popen([str(responder)], cwd=folder,
                    env=dict(environment, RAGNAROK_CURRENT_SEQUENCE_CASE=name),
                    stdout=output, stderr=subprocess.STDOUT)
                port = ready_port(process, folder)
                arguments = [str(peer), 'download-current', str(port),
                    environment['RAGNAROK_TEST_CERT'], environment['RAGNAROK_TEST_KEY'],
                    environment['RAGNAROK_TEST_PEER_B'], 'jamnp-s/1/00000000',
                    '4000' if name == 'timeout' else '10000', 'current-policy.conf',
                    '--with-state', '--chain', 'current-chain.json', '--state-writes', '1000',
                    '--state-write-bytes', '1000000', '--state-storage', 'disk',
                    '--state-db', 'current-state.db', '--download-blocks', '3']
                if name in ('managed', 'managed-resumed', 'empty', 'managed-maintenance',
                            'maintenance-resource', 'maintenance-resumed'):
                    arguments += ['--state-layout', 'managed', '--state-compact-bytes',
                                  '1' if 'maintenance' in name else '0']
                runs = []
                for step, requested in enumerate((1, 2) if name.endswith('-resumed') else (3,)):
                    # A fresh executable lifetime must select the prefix persisted by the previous one.
                    command = list(arguments)
                    command[command.index('--download-blocks')+1] = str(requested)
                    result = subprocess.run(command, cwd=folder, env=environment,
                        capture_output=True, text=True, timeout=20)
                    (folder/f'application-{step}.stdout').write_text(result.stdout)
                    (folder/f'application-{step}.stderr').write_text(result.stderr)
                    adopted = 2 if partial else requested
                    marker = 'FAILED Timeout' if name == 'timeout' else ('FAILED Exhausted' if partial else 'ADOPTED')
                    progress = f'CURRENT_DOWNLOAD_PROGRESS adopted={adopted} requested={requested}'
                    passed = (result.returncode == (2 if partial else 0)
                        and 'CURRENT_DOWNLOAD_'+marker in (result.stdout+result.stderr).splitlines()
                        and (requested == 1 or progress in result.stdout.splitlines()))
                    runs.append(dict(command=command, exit_code=result.returncode, passed=passed))
                    if not passed:
                        raise ValueError('Consecutive current executable transcript failed: '+str(folder))
                    if step == 0 and name.endswith('-resumed'):
                        # The independent fixture listener admits one connection; rebind before the fresh command.
                        (folder/'current-ready').unlink()
                        (folder/'current-next').write_text('next')
                        arguments[2] = str(ready_port(process, folder))
                (folder/'current-stop').write_text('stop')
                code = process.wait(timeout=10)
            # Each complete CLI transcript and the independent full-history witness must agree.
            adopted = 2 if partial else 3
            verified = f'CURRENT_SEQUENCE_VERIFIED adopted={adopted} requests=3'
            passed = code == 0 and verified in log.read_text().splitlines() and all(r['passed'] for r in runs)
            row = dict(case=name, runs=runs, responder_exit_code=code, responder_log=str(log), passed=passed)
            rows.append(row)
            if not passed:
                raise ValueError('Executable current sequence verification failed: '+str(row))
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
