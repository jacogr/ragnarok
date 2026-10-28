# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Observe actual current-command exits and progress alongside an independent native TLS/map witness.

Exposes observe, observe_preimages, observe_guarantees and observe_rotated; process failures always reap the responder and cannot borrow another case's verdict.
"""
import subprocess
import tempfile
from pathlib import Path

from application_current_download import ready_port


def _observe(peer, responder, directory, environment, cases, extra=(), context_requests=0):
    """Check each current command transcript and independent durable prefix before the next case."""
    directory.mkdir(parents=True, exist_ok=True)
    if (not cases or context_requests not in (0, 1)
            or any(total not in (2, 3) for _, total, _ in cases)):
        raise ValueError('Current sequence case plan must contain bounded two/three-child cases')
    rows = []
    for name, total, partial in cases:
        folder = Path(tempfile.mkdtemp(prefix=name+'-', dir=directory))
        log = folder/'responder.log'
        process = None
        try:
            with log.open('w') as output:
                process = subprocess.Popen([str(responder)], cwd=folder,
                    env=dict(environment, RAGNAROK_CURRENT_SEQUENCE_CASE=name),
                    stdout=output, stderr=subprocess.STDOUT)
                port = ready_port(process, folder)
                arguments = [str(peer), 'download-current', '--net-port', str(port),
                    '--net-cert', environment['RAGNAROK_TEST_CERT'], '--net-key', environment['RAGNAROK_TEST_KEY'],
                    '--net-peer-key', environment['RAGNAROK_TEST_PEER_B'], '--net-alpn', 'jamnp-s/1/00000000',
                    '--net-timeout-ms', '4000' if name in ('timeout', 'guarantees-timeout') else '10000', '--download-policy', 'current-policy.conf',
                    '--with-state', '--chain', 'current-chain.json', '--state-writes', '1000',
                    '--state-write-bytes', '1000000', '--state-storage', 'disk',
                    '--state-db', 'current-state.db', '--download-blocks', str(total)]
                if name in ('managed', 'managed-resumed', 'empty', 'managed-maintenance',
                            'maintenance-resource', 'maintenance-resumed', 'preimages-managed',
                            'preimages-repeated', 'guarantees-managed', 'guarantees-wrong',
                            'rotated-managed', 'rotated-maintenance', 'rotated-resource'):
                    arguments += ['--state-layout', 'managed', '--state-compact-bytes',
                                  '1' if 'maintenance' in name else '0']
                arguments += list(extra) # Source-owned acquisition options never alter the shared credential/endpoint tuple.
                runs = []
                for step, requested in enumerate((1, total-1) if name.endswith('-resumed') else (total,)):
                    # A fresh executable lifetime must select the prefix persisted by the previous one.
                    command = list(arguments)
                    command[command.index('--download-blocks')+1] = str(requested)
                    result = subprocess.run(command, cwd=folder, env=environment,
                        capture_output=True, text=True, timeout=20)
                    (folder/f'application-{step}.stdout').write_text(result.stdout)
                    (folder/f'application-{step}.stderr').write_text(result.stderr)
                    adopted = total-1 if partial else requested
                    marker = 'FAILED Timeout' if name in ('timeout', 'guarantees-timeout') else ('FAILED Exhausted' if partial else 'ADOPTED')
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
                        arguments[arguments.index('--net-port')+1] = str(ready_port(process, folder))
                (folder/'current-stop').write_text('stop')
                code = process.wait(timeout=10)
            # Each complete CLI transcript and the independent full-history witness must agree.
            adopted = total-1 if partial else total
            verified = f'CURRENT_SEQUENCE_VERIFIED adopted={adopted} requests={total+context_requests}'
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


def observe(peer, responder, directory, environment):
    """Preserve the ordinary three-child success, maintenance, refusal and restart plan."""
    cases = [('journal', 3, False), ('managed', 3, False), ('journal-resumed', 3, False),
             ('managed-resumed', 3, False), ('replay', 3, True), ('empty', 3, True),
             ('timeout', 3, True), ('resource', 3, True), ('managed-maintenance', 3, False),
             ('maintenance-resource', 3, True), ('maintenance-resumed', 3, False)]
    return _observe(peer, responder, directory, environment, cases)


def observe_preimages(peer, responder, directory, environment):
    """Separate nonempty delivery cases require two adoptions and fresh third-body refusal."""
    cases = [('preimages-journal', 2, False), ('preimages-managed', 2, False),
             ('preimages-repeated', 3, True), ('preimages-resumed', 2, False)]
    return _observe(peer, responder, directory, environment, cases)


def observe_guarantees(peer, responder, directory, environment):
    """Current blocks and one separately counted original-context request must all receive independent verification."""
    cases = [('guarantees-journal', 2, False), ('guarantees-managed', 2, False),
             ('guarantees-wrong', 2, True), ('guarantees-timeout', 2, True)]
    return _observe(peer, responder, directory, environment, cases,
                    extra=('--download-discover-ancestors', '1'), context_requests=1)


def observe_rotated(peer, responder, directory, environment):
    """Verify the actual rotated selected state through durable success, restart, maintenance and a bounded prefix."""
    cases = [('rotated-journal', 3, False), ('rotated-managed', 3, False),
             ('rotated-resumed', 3, False), ('rotated-maintenance', 3, False),
             ('rotated-resource', 3, True)]
    return _observe(peer, responder, directory, environment, cases)
