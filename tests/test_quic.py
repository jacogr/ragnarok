#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Provide TLS fixtures and bounded process checks for the unified JAMNP-S CE 143 application.

Exposes application_binaries, peer_name, fixtures, thread_count, wait_server_ready and attempt
for the verification harness.
"""
import json
from pathlib import Path
import platform
import shutil
import socket
import subprocess
import sys
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from build_quic import ROOT, BUILD, PINS

# The shipped application owns one dispatcher and one bounded logging writer by default.
THREAD_BASELINES = {'nim': 2}
# The original bounded authentication and framing matrix is shared by the Nimony migration runner.
SCENARIOS = ('valid', 'wrong-san', 'no-san', 'multi-san', 'ecdsa', 'wrong-signature', 'missing-cert', 'bad-server-san',
             'wrong-server-key', 'wrong-alpn', 'bad-kind', 'oversize', 'unknown', 'truncated', 'trailing', 'no-fin')

# Serialize only UDP reservation-to-readiness handoff; authenticated exchanges still run concurrently.
STARTUP_LOCK = threading.Lock()


# E2E defaults always use the built application; explicit overrides select isolated profiles/fixtures.
def application_binaries(binaries=None):
    """Resolve both network roles to the common app without resurrecting language-specific clients."""
    return binaries or {'nim': ROOT/'build/ragnarok'}


# Compute the literal pinned SAN formula independently using arbitrary precision, not native bit loops or standard base32.
def peer_name(key):
    value = int.from_bytes(key, 'little')
    alphabet = '$abcdefghijklmnopqrstuvwxyz234567'
    result = '$e'
    for _ in range(52):
        result += alphabet[value % 32]
        value //= 32
    return result


# Generate local test identities only; private keys stay inside the ignored build directory and are never committed.
def fixtures(folder=None):
    # A caller may isolate retained TLS identities from other concurrently running proof harnesses.
    folder = BUILD / 'fixtures' if folder is None else folder
    folder.mkdir(parents=True, exist_ok=True)
    openssl = shutil.which('openssl')
    assert openssl
    # Structured OpenSSL arguments avoid shell expansion; escaped dollars are needed in OpenSSL's config syntax.
    for identity in ('a', 'b', 'c', 'd', 'e', 'wrong-san', 'no-san', 'multi-san', 'ecdsa'):
        key, cert = folder / f'{identity}.key.pem', folder / f'{identity}.cert.pem'
        algorithm = ['-algorithm', 'EC', '-pkeyopt', 'ec_paramgen_curve:P-256'] if identity == 'ecdsa' else ['-algorithm', 'ED25519']
        subprocess.run([openssl, 'genpkey', *algorithm, '-out', key], check=True, capture_output=True)
        public = subprocess.check_output([openssl, 'pkey', '-in', key, '-pubout', '-outform', 'DER'])
        raw = public[-32:]
        # Valid Ed25519 fixture keys must have the expected exact SPKI representation, not merely a matching suffix.
        if identity != 'ecdsa':
            assert public == bytes.fromhex('302a300506032b6570032100') + raw
        (folder / f'{identity}.pub').write_bytes(raw)
        san = '$e' + 'a' * 52 if identity == 'wrong-san' else peer_name(raw)
        args = [openssl, 'req', '-new', '-x509', '-key', key, '-out', cert, '-days', '2', '-subj', '/CN=ragnarok-quic-proof']
        if identity != 'no-san':
            value = san.replace('$', r'\$') + (',DNS:extra' if identity == 'multi-san' else '')
            args += ['-addext', 'subjectAltName=DNS:' + value]
        subprocess.run(args, check=True, capture_output=True)
    # Isolate the certificate-signature check: an Ed25519 leaf key signed by the ECDSA fixture CA must still be rejected.
    identity = 'wrong-signature'
    key, cert = folder / f'{identity}.key.pem', folder / f'{identity}.cert.pem'
    subprocess.run([openssl, 'genpkey', '-algorithm', 'ED25519', '-out', key], check=True, capture_output=True)
    public = subprocess.check_output([openssl, 'pkey', '-in', key, '-pubout', '-outform', 'DER'])
    raw = public[-32:]
    assert public == bytes.fromhex('302a300506032b6570032100') + raw
    (folder / f'{identity}.pub').write_bytes(raw)
    csr = folder / f'{identity}.csr'
    subprocess.run([openssl, 'req', '-new', '-key', key, '-out', csr, '-subj', '/CN=ragnarok-quic-proof',
                    '-addext', 'subjectAltName=DNS:' + peer_name(raw).replace('$', r'\$')], check=True, capture_output=True)
    subprocess.run([openssl, 'x509', '-req', '-in', csr, '-CA', folder / 'ecdsa.cert.pem', '-CAkey', folder / 'ecdsa.key.pem',
                    '-set_serial', '7', '-days', '2', '-copy_extensions', 'copy', '-out', cert], check=True, capture_output=True)
    return folder


# Observe OS thread counts during stalled concurrent streams; this is a snapshot, not a sustained-load capacity claim.
def thread_count(pid):
    if platform.system() == 'Darwin':
        output = subprocess.check_output(['ps', '-M', '-p', str(pid)], text=True)
        return max(0, len(output.strip().splitlines()) - 1)
    return len(list(Path(f'/proc/{pid}/task').iterdir()))


# Require a live bound listener and an exact marker; preserve startup diagnostics on exit or timeout.
def wait_server_ready(process, path, case, seconds=3):
    deadline = time.monotonic() + seconds
    # Poll a file rather than blocking on an unbounded pipe readline from a stalled child.
    while True:
        output = path.read_text()
        code = process.poll()
        # A dead listener cannot serve a client even if it printed READY just before exiting.
        if code is not None:
            raise AssertionError(dict(case=case, phase='server startup', reason='exited',
                                      exit_code=code, log_path=str(path), server_output=output[-8000:]))
        # Diagnostics containing the word READY are not the listener's lifecycle marker.
        if 'READY' in output.splitlines():
            return
        # Keep the existing three-second startup deadline; a slow/hung server remains a failure.
        if time.monotonic() >= deadline:
            raise AssertionError(dict(case=case, phase='server startup', reason='timeout',
                                      exit_code=code, log_path=str(path), server_output=output[-8000:]))
        time.sleep(0.01)


# Execute one independently bounded localhost peer pair and retain diagnostics without printing any private-key contents.
def attempt(case, folder, binaries=None, logs=None):
    server_language, client_language, scenario = case
    # Isolated app profiles reuse the exact baseline workload without overwriting the production binary.
    binaries = application_binaries(binaries)
    client_identity = scenario if scenario in ('wrong-san', 'no-san', 'multi-san', 'ecdsa', 'wrong-signature') else 'b'
    server_identity = 'wrong-san' if scenario == 'bad-server-san' else 'a'
    expected = 'b' if scenario == 'wrong-server-key' else 'a'
    alpn = 'jamnp-s/1/00000000'
    client_alpn = 'jamnp-s/1/11111111' if scenario == 'wrong-alpn' else alpn
    cert = lambda name: str(folder / f'{name}.cert.pem')
    key = lambda name: str(folder / f'{name}.key.pem')
    server = [str(binaries[server_language]), 'server', '--net-port', '0', '--net-cert', cert(server_identity), '--net-key', key(server_identity), '--net-peer-key', '-', '--net-alpn', alpn, '--net-timeout-ms', '900', '--net-mode', 'valid']
    client = [str(binaries[client_language]), 'client', '--net-port', '0',
              '--net-cert', '-' if scenario == 'missing-cert' else cert(client_identity),
              '--net-key', '-' if scenario == 'missing-cert' else key(client_identity), '--net-peer-key', str(folder / f'{expected}.pub'), '--net-alpn', client_alpn, '--net-timeout-ms', '900']
    application_failure = scenario in ('bad-kind', 'oversize', 'unknown', 'truncated', 'trailing', 'no-fin')
    if application_failure:
        client += ['--net-mode', scenario]
    logs = BUILD / 'cases' if logs is None else logs
    logs.mkdir(parents=True, exist_ok=True)
    path = logs / '-'.join(case)
    process = None
    client_process = None
    # Server readiness uses a log file plus a deadline, avoiding an unbounded pipe readline if startup hangs.
    with path.with_suffix('.server.log').open('w') as server_log:
        try:
            # Other workers cannot select this released port before the native listener claims it.
            with STARTUP_LOCK:
                # QUIC binds UDP: a TCP reservation does not exclude an existing UDP owner.
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
                    reservation.bind(('127.0.0.1', 0))
                    port = reservation.getsockname()[1]
                    server[server.index('--net-port')+1] = client[client.index('--net-port')+1] = str(port)
                # Release immediately before spawn; readiness proves the native listener owns the port.
                process = subprocess.Popen(server, stdout=server_log, stderr=subprocess.STDOUT)
                wait_server_ready(process, path.with_suffix('.server.log'), case)
            client_process = subprocess.Popen(client, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            observed_threads = None
            # Missing FIN keeps all eight requests pending, allowing a live thread observation before the deadline.
            if scenario == 'no-fin':
                time.sleep(0.1)
                observed_threads = {'server': thread_count(process.pid), 'client': thread_count(client_process.pid)}
                assert observed_threads == {'server': THREAD_BASELINES[server_language], 'client': THREAD_BASELINES[client_language]}, (case, observed_threads, THREAD_BASELINES)
            client_out, client_err = client_process.communicate(timeout=4)
            result = subprocess.CompletedProcess(client, client_process.returncode, client_out, client_err)
            process.wait(timeout=4)
            server_output = path.with_suffix('.server.log').read_text()
            valid = scenario == 'valid'
            assert (result.returncode == 0 and process.returncode == 0) == valid, (case, server_output, result.stdout, result.stderr)
            assert ('EXCHANGE_OK 8' in server_output and 'EXCHANGE_OK 8' in result.stdout) == valid, case
            # Malformed application tests must reach authenticated transport first, or they are not meaningful framing tests.
            if application_failure:
                assert 'AUTH_OK' in server_output and 'AUTH_OK' in result.stdout, (case, server_output, result.stdout)
            return {'server': server_language, 'client': client_language, 'scenario': scenario,
                    'server_exit': process.returncode, 'client_exit': result.returncode, 'observed_threads': observed_threads,
                    'server_stdout': server_output, 'client_stdout': result.stdout, 'client_stderr': result.stderr}
        finally:
            # Retire orphaned servers after assertion/process timeout, leaving no listener running after the suite.
            for active in (client_process, process):
                if active is not None and active.poll() is None:
                    active.kill()
                    active.wait()
