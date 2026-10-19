#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify real peer exchanges, retained services, resilience, soak and proof-offload lifecycles.

Exposes passed and an E2E CLI that runs owned workloads and writes a fresh completeness verdict.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys
import time
from native_checks import NativeChecks, ROOT, announce
from runtime_provenance import runtime_sources
from e2e_checks import PLAN, run

BUILD = ROOT/'build/tests/e2e'
# Compatibility views derive from executable task declarations; there is no second coverage list.
WORKLOADS = PLAN.names('workload')
SELFTESTS = PLAN.names('selftest')


# Completeness and execution share one pre-execution plan, independent of observed successes.
def passed(report):
    """Require every declared lifecycle and selftest to have passed in this invocation."""
    return PLAN.passed(report)


# Provision this group's own native bridges and fixtures; no earlier unit run or binary is required.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    compiler = parser.parse_args().compiler.resolve()
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD/'results.json').unlink(missing_ok=True)
    started = time.monotonic()
    report = dict(status='failed', suites=[], environment=dict(system=platform.system(),
                  machine=platform.machine(), python=platform.python_version()))
    checks = NativeChecks(BUILD)
    try:
        # Preserve compiler/revision and native pin evidence independently of any other CI job.
        metadata = compiler.parent.parent/'NIGHTLY.txt'
        report['nightly_metadata'] = metadata.read_text() if metadata.is_file() else None
        # Shared source-family discovery covers new transitive modules and helpers automatically.
        sources = runtime_sources()
        report['sources'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                             for path in sources}
        report['compiler'] = checks.command([compiler, '--version'], 'compiler')
        report['project_revision'] = checks.command(['git', 'rev-parse', 'HEAD'], 'revision')['output'].strip()
        sys.path.insert(0, str(ROOT/'tests'))
        from nimony_crypto import prepare as prepare_crypto
        from bandersnatch_native import prepare as prepare_bandersnatch
        from nimony_quic import prepare as prepare_quic
        crypto, _, report['crypto_native'] = prepare_crypto(BUILD)
        bs, _, report['bandersnatch_native'] = prepare_bandersnatch(BUILD)
        quic, certificates, report['quic_native'] = prepare_quic()
        import test_integration as integration_fixture
        integration_fixture.BUILD.mkdir(parents=True, exist_ok=True)
        wires, _ = integration_fixture.corpus()
        report['fixture_sha256'] = {str(i): hashlib.sha256((wires/f'{i}.bin').read_bytes()).hexdigest()
                                   for i in range(8)}
        run(compiler, crypto, bs, quic, certificates, wires, report, checks)
        report['status'] = 'checks-passed' if passed(report) else 'failed'
    except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
        # Setup, compilation and workload exceptions remain failures with retained diagnostics.
        report['failure'] = repr(error)
    finally:
        # Interrupted/failed preparation cannot leave a previous successful report current.
        report['elapsed_seconds'] = round(time.monotonic()-started, 6)
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    announce('E2E networking verification', report['status'] == 'checks-passed')
    print('Evidence: '+str(BUILD.relative_to(ROOT)/'results.json'))
    raise SystemExit(0 if report['status'] == 'checks-passed' else 1)


# Importing this inventory never builds native dependencies or starts peers.
if __name__ == '__main__':
    main()
