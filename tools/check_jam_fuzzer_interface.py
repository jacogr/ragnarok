#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run the current JAM fuzz interface's fixed independent corpora and real-entry socket checks.

This opt-in CI group validates the engine interface, not a generated campaign. A compatible
polkajam-fuzz engine remains a separate prerequisite. Make owns all dependency setup.
"""
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys
import time
from types import SimpleNamespace
from native_checks import NativeChecks, ROOT, announce
from runtime_provenance import runtime_sources
from setup_nimony import installed
from corpus_state import CORPORA

BUILD = ROOT/'build/tests/jam-fuzzer-interface'
# Source-owned corpus declarations supply identities; the feature prefix selects this opt-in scope.
CASES = tuple(sorted(name for name in CORPORA.tasks if name.startswith('jam_fuzzer_')))


def passed(report):
    """Require the entire declared interface scope; a missing, skipped or failed child cannot pass."""
    cases = report.get('cases', {})
    return (bool(CASES) and set(cases) == set(CASES) and all(cases[name].get('passed') is True for name in CASES)
            and report.get('socket', {}).get('passed') is True)


def summary(report):
    """Distinguish actual interface verdicts from unavailable live generated campaign validation."""
    lines = ['# JAM fuzzer interface', '',
             'Interface checks: '+('passed' if passed(report) else 'failed'), '',
             'Live generated campaign validation: pending compatible polkajam-fuzz engine.', '',
             '| Check | Result |', '| --- | --- |']
    for name in CASES:
        result = report.get('cases', {}).get(name)
        lines.append('| '+name+' | '+('passed' if result and result.get('passed') else 'failed or missing')+' |')
    lines.append('| real-entry socket | '+('passed' if report.get('socket', {}).get('passed') else 'failed or missing')+' |')
    return '\n'.join(lines)+'\n'


def main():
    """Provision independent native owners, execute registered cases sequentially and retain fresh failure evidence."""
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD/'results.json').unlink(missing_ok=True)
    (BUILD/'summary.md').unlink(missing_ok=True)
    started = time.monotonic()
    report = dict(status='failed', cases={}, engine_validation='pending',
                  scope='fixed current-profile interface cases; no generated campaign',
                  environment=dict(system=platform.system(), machine=platform.machine()))
    try:
        compiler, _ = installed()
        checks = NativeChecks(BUILD, reuse_builds=True)
        report['compiler'] = checks.command([compiler, '--version'], 'compiler')
        report['revision'] = checks.command(['git', 'rev-parse', 'HEAD'], 'revision')['output'].strip()
        report['sources'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                             for path in runtime_sources()}
        sys.path.insert(0, str(ROOT/'tests'))
        from nimony_crypto import prepare as prepare_crypto
        from bandersnatch_native import prepare as prepare_bandersnatch
        from nimony_quic import prepare as prepare_quic
        import e2e_checks
        crypto, _, report['crypto_native'] = prepare_crypto(BUILD)
        bs, _, report['bandersnatch_native'] = prepare_bandersnatch(BUILD)
        quic, _, report['quic_native'] = prepare_quic()
        libraries = dict(crypto=crypto, bandersnatch=bs, quic=quic)
        for name in CASES:
            # These are the registered independent references; native results never calculate expected maps.
            report['cases'][name] = CORPORA.tasks[name](compiler, report, checks, libraries)
            if not report['cases'][name]['passed']:
                raise AssertionError('Failed interface corpus: '+name)
        context = SimpleNamespace(compiler=compiler, checks=checks, report=report, crypto=crypto, bs=bs, quic=quic)
        e2e_checks.prepare_peer(context)
        e2e_checks.prepare_fuzzer_policy(context)
        report['socket'] = e2e_checks.application_fuzzer_interface(context)
        report['status'] = 'checks-passed' if passed(report) else 'failed'
    except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
        # A partial invocation cannot reuse another group's success or an earlier results file.
        report['failure'] = repr(error)
    finally:
        report['elapsed_seconds'] = round(time.monotonic()-started, 6)
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
        (BUILD/'summary.md').write_text(summary(report))
    success = report['status'] == 'checks-passed' and passed(report)
    announce('JAM fuzzer interface verification', success)
    return 0 if success else 1


if __name__ == '__main__':
    raise SystemExit(main())
