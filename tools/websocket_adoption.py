#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Assess stock WebSocket slow-peer closure in an isolated, bounded child process.

A completed assessment reports evidence, never transport qualification. Unknown failures fail
this command. Configured Darwin listeners must retire cleanly; other platform defaults may
still expose the witnessed SIGPIPE blocker. RPC adoption remains a separate qualification.
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


def classify(returncode, output, *, require_clean_exit=False):
    """Require exact witnesses; configured listeners must reach joined cleanup without a signal."""
    if returncode == -signal.SIGPIPE and output == PREFIX and not require_clean_exit:
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
    outcome = classify(result['exit_code'], result['output'],
                       require_clean_exit=platform.system() == 'Darwin')
    record = {'adoption': 'not-qualified', 'build': built, 'host': platform.platform(),
              'macos_listener_nosigpipe': platform.system() == 'Darwin',
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
