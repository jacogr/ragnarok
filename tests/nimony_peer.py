# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Replay the original authenticated CE 143 matrix against an isolated checked Nimony peer."""
import subprocess
from test_quic import SCENARIOS, attempt


# A fresh process pair must authenticate and complete application work, or reject at the original stage.
def exchanges(binary, fixtures, folder):
    rows = []
    # Keep original scenarios, certificate identities, deadlines, framing bytes and thread observation intact.
    for scenario in SCENARIOS:
        row = attempt(('nim', 'nim', scenario), fixtures, {'nim': binary}, folder)
        expected = 0 if scenario == 'valid' else 2
        # Each endpoint must have the expected outcome; one failed endpoint cannot hide a successful peer.
        assert row['server_exit'] == row['client_exit'] == expected, row
        rows.append(row)
    # Repeated cold startups catch accidental reuse/uninitialized admission flags independently of parser tests.
    for repeat in range(12):
        row = attempt(('nim', 'nim', 'valid'), fixtures, {'nim': binary}, folder/f'repeat-{repeat}')
        assert row['server_exit'] == row['client_exit'] == 0, row
        rows.append(row)
    return dict(passed=True, cases=rows, matrix_cases=len(SCENARIOS), repeated_valid=12,
                scope='one-shot authenticated IPv4 CE 143; service/mesh/resilience/offload remain separate')


# Trusted malformed controls must fail before announcing a listener or accepting any application work.
def controls(binary, fixtures):
    base = ['client', '1', str(fixtures/'b.cert.pem'), str(fixtures/'b.key.pem'),
            str(fixtures/'a.pub'), 'jamnp-s/1/00000000', '900']
    cases = [('arity', []), ('role', ['other', *base[1:]]),
             ('telemetry-missing-endpoint', ['server', *base[1:], '--telemetry']),
             ('telemetry-nontrailing', ['--telemetry', '127.0.0.1:9000', *base]),
             ('telemetry-duplicate', [*base, '--telemetry', '127.0.0.1:9000', '--telemetry', '127.0.0.1:9001']),
             ('chain-missing-value', [*base, '--telemetry', '127.0.0.1:9000', '--chain']),
             ('chain-missing-option', [*base, '--telemetry', '127.0.0.1:9000']),
             ('chain-without-telemetry', [*base, '--chain', 'unused.json']),
             ('chain-duplicate', [*base, '--chain', 'a.json', '--chain', 'b.json']),
             ('chain-option-as-value', [*base, '--chain', '--chain', '--telemetry', '127.0.0.1:9000']),
             ('telemetry-selftest', ['--selftest', '--telemetry', '127.0.0.1:9000'])]
    # Host/native port narrowing and deadline validation must precede opening any endpoint.
    for text in ('0', '-1', '65536', 'not-a-port'):
        args = base.copy()
        args[1] = text
        cases.append(('port-'+text, args))
    for text in ('0', '120001', 'not-a-timeout'):
        args = base.copy()
        args[6] = text
        cases.append(('timeout-'+text, args))
    rows = []
    for name, args in cases:
        result = subprocess.run([str(binary), *args], capture_output=True, text=True, timeout=4)
        # Fail closed after trusted parsing errors; exact diagnostics may differ from ordinary protocol rejection.
        assert result.returncode != 0 and 'READY' not in result.stdout and 'AUTH_OK' not in result.stdout, (name, result)
        rows.append(dict(name=name, exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr))
    return dict(passed=True, cases=rows)
