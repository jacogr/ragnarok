#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify real peer exchanges, retained services, resilience, soak and proof-offload lifecycles."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys
import time
from native_checks import NativeChecks, ROOT, announce
from e2e_checks import run

BUILD = ROOT/'build/tests/e2e'
# Each lifecycle has a distinct required verdict; an omitted workload is never an implicit pass.
WORKLOADS = ('rpc', 'telemetry', 'quic_peer', 'quic_peer_controls', 'quic_service', 'quic_integration_service',
             'quic_mesh', 'quic_mesh_disruption', 'quic_endpoint_soak', 'quic_admission',
             'quic_closed_before_request', 'quic_offload')
# Entry-point and shutdown selftests remain covered once, alongside the binaries used by live workloads.
SELFTESTS = ('quic_peer_parser', 'quic_peer_io', 'quic_peer_mesh_policy',
             'quic_peer_integration', 'offload_capacity', 'offload_held_shutdown')


# Require every real scenario and every entry-point selftest, not just a nonempty report.
def passed(report):
    return (len(report['suites']) == len(SELFTESTS)
            and {row['name'] for row in report['suites']} == set(SELFTESTS)
            and all(row['passed'] for row in report['suites'])
            and all(report.get(name, {}).get('passed', False) for name in WORKLOADS))


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
        sources = [Path(__file__), ROOT/'tools/e2e_checks.py', ROOT/'tools/native_checks.py', ROOT/'tools/native_dependencies.py', ROOT/'tools/build_crypto.py', ROOT/'tools/build_bandersnatch.py', ROOT/'tools/build_quic.py',
                   ROOT/'spec/toolchain.json', ROOT/'spec/quic-proof-pins.json',
                   ROOT/'spec/bandersnatch-pins.json', *sorted((ROOT/'src/quic').glob('*.nim')),
                   *sorted((ROOT/'src/telemetry').glob('*.nim')), ROOT/'tests/telemetry_checks.py', ROOT/'tests/fixtures/telemetry-dev.json',
                   *sorted((ROOT/'src/rpc').glob('*.nim')), *sorted((ROOT/'src/chain').glob('*.nim')), ROOT/'tests/rpc_checks.py',
                   ROOT/'tests/fixtures/rpc-parameters.json', ROOT/'tests/fixtures/rpc-parameters-result.json',
                   *[ROOT/'tests'/name for name in ('nimony_peer.py', 'test_quic_service.py',
                     'test_quic_mesh.py', 'test_quic_resilience.py', 'test_quic_soak.py',
                     'test_quic_offload.py', 'test_integration.py')]]
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
