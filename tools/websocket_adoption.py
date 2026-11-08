#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Assess stock WebSocket slow-peer closure in an isolated, bounded child process.

A completed assessment reports evidence, never transport qualification. Unknown failures fail
this command; the specific witnessed SIGPIPE outcome remains an explicit adoption blocker.
"""
import hashlib
import json
import platform
import signal
from native_checks import NativeChecks, ROOT
from setup_nimony import installed

PREFIX = ('probe: upgrades=8\n'
          'probe: delivered=7\n'
          'probe: unsolicited frames verified\n'
          'probe: writer abort leaves readers pending=8\n'
          'probe: closing peers\n')
COMPLETE = PREFIX + 'probe: task owners retired and pool joined\n'


def classify(returncode, output):
    """Require the exact fairness witnesses before recognizing either supported close outcome."""
    if returncode == -signal.SIGPIPE and output == PREFIX:
        # Only this signal after all witnesses identifies the observed slow-peer close blocker.
        return 'blocked-by-sigpipe'
    if returncode == 0 and output == COMPLETE:
        # Clean peer-driven retirement still does not prove local cancellation or RPC integration.
        return 'peer-close-retired'
    raise ValueError(f'Unrecognized WebSocket probe outcome: exit {returncode}')


def main():
    """Compile the current source, retire old evidence, and retain exact host/process outcomes."""
    folder = ROOT/'build/tests/websocket-adoption'
    folder.mkdir(parents=True, exist_ok=True)
    report = folder/'assessment.json'
    report.unlink(missing_ok=True)
    compiler, _ = installed()
    checks = NativeChecks(folder)
    built, binary = checks.build(compiler, ROOT/'tests/native/websocket_slow_peer.nim',
                                 'slow-peer', timeout=180)
    if built['exit_code'] != 0:
        # A stale binary cannot substitute for the current source's failed build.
        raise RuntimeError('WebSocket probe build failed; see '+built['log'])
    result = checks.command([binary], 'slow-peer-runtime', timeout=20)
    outcome = classify(result['exit_code'], result['output'])
    record = {'adoption': 'not-qualified', 'build': built, 'host': platform.platform(),
              'inputs': {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in
                         ('spec/toolchain.json', 'tests/native/websocket_slow_peer.nim',
                          'tests/support/websocket_adoption.nim', 'tools/websocket_adoption.py')},
              'outcome': outcome, 'runtime': result,
              'toolchain': json.loads((ROOT/'spec/toolchain.json').read_text())['commit']}
    report.write_text(json.dumps(record, indent=2)+'\n')
    print('WebSocket assessment: '+outcome+'; adoption remains not-qualified')
    print('Evidence: '+str(report.relative_to(ROOT)))


if __name__ == '__main__':
    # Exceptions/timeouts remain nonzero failures instead of being reclassified as known blockers.
    main()
