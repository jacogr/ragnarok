# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exercise explicit executable state policies through real peer and retained mesh lifecycles.

Exposes run; protocol assertions reuse the independent RPC wire harness while startup
refusals and owned child cleanup remain bounded process-level checks.
"""
from contextlib import ExitStack
from pathlib import Path
import os
import socket
import subprocess
import time
from rpc_checks import run as rpc_run, ready
from test_quic_mesh import ports, observe
from test_quic import THREAD_BASELINES


# Choose an unused local UDP endpoint without fixed machine-wide test ports.
def peer_port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(('127.0.0.1', 0))
        return str(reservation.getsockname()[1])


# The sole executable owns one complete state seed even when neither RPC nor telemetry is enabled.
def standalone(binary, certificates, chain, folder, policy):
    folder.mkdir(parents=True, exist_ok=True)
    log, stop = folder/'peer.log', folder/'stop'
    stop.unlink(missing_ok=True)
    command = [str(binary), 'server', '--net-port', peer_port(), '--net-cert', str(certificates/'a.cert.pem'),
               '--net-key', str(certificates/'a.key.pem'), '--net-peer-key', '-', '--net-alpn', 'jamnp-s/1/00000000', '--net-timeout-ms', '30000', '--net-mode', 'service',
               '--chain', str(chain), *policy]
    with log.open('wb') as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                                   env={**os.environ, 'RAGNAROK_SERVICE_STOP': str(stop)})
        try:
            ready(process, log)
            stop.touch()
            # An empty proof workload refuses after successful startup; normal ARC/native teardown still completes.
            assert process.wait(timeout=5) == 2, log.read_text()
            assert 'SERVICE_DONE 0 0 0' in log.read_text()
        finally:
            # Reap before the diagnostic stream closes, including failed readiness or timeout.
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)


# Both retained role engines borrow the same canonical service owner until one genuine exchange and clean exit.
def mesh(binary, certificates, chain, folder, policy):
    folder.mkdir(parents=True, exist_ok=True)
    gate = folder/('gate-'+str(time.time_ns()))
    gate.mkdir()
    selected = ports()
    processes, logs, peaks = {}, {}, {}
    with ExitStack() as handles:
        try:
            for index, role in enumerate(('a', 'b')):
                other = 'b' if role == 'a' else 'a'
                logs[role] = folder/(role+'.log')
                peaks[role] = {}
                command = [str(binary), 'mesh', '--net-local-port', str(selected[index]), '--net-remote-port', str(selected[1-index]),
                           '--net-cert', str(certificates/(role+'.cert.pem')), '--net-key', str(certificates/(role+'.key.pem')),
                           '--net-local-key', str(certificates/(role+'.pub')), '--net-peer-key', str(certificates/(other+'.pub')),
                           '--net-alpn', 'jamnp-s/1/00000000', '--net-gate', str(gate), '--chain', str(chain), *policy]
                output = handles.enter_context(logs[role].open('wb'))
                processes[role] = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                    env={**os.environ, 'RAGNAROK_MESH_ROUNDS': '1', 'RAGNAROK_MESH_FALLBACK': '0',
                         'RAGNAROK_MESH_DISRUPT': '0'})
            # The shared baseline includes the dispatcher and the enabled bounded logging writer.
            thread_limits = {role: THREAD_BASELINES['nim'] for role in processes}
            observe(processes, logs, 'MESH_READY ', peaks, thread_limits=thread_limits)
            (gate/'start-0').touch()
            texts = observe(processes, logs, 'MESH_EXCHANGED 0 ', peaks, thread_limits=thread_limits)
            assert all('MESH_EXCHANGED 0 8' in text.splitlines() for text in texts.values())
            (gate/'close-0').touch()
            observe(processes, logs, 'MESH_IDLE 0 ', peaks, thread_limits=thread_limits)
            (gate/'stop').touch()
            for role, process in processes.items():
                assert process.wait(timeout=5) == 0, logs[role].read_text()
                clean = [line.split() for line in logs[role].read_text().splitlines() if line.startswith('MESH_CLEAN ')]
                assert len(clean) == 1, clean
                assert int(clean[0][2]) <= int(clean[0][1]) + 65536, clean
        finally:
            # Every owned process retires before its file handles, even if the second startup fails.
            for process in processes.values():
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)


# Run one feature workload with shared pristine certificates and the normal executable from E2E setup.
def run(binary, certificates, folder):
    folder.mkdir(parents=True, exist_ok=True)
    chain = folder/'chain.json'
    seed = (Path(__file__).parent/'fixtures/rpc-genesis.json').read_text()
    chain.write_text(seed)
    policy = ['--with-state', '--state-writes', '1000', '--state-write-bytes', '1000000']
    standalone(binary, certificates, chain, folder/'standalone', policy)
    mesh(binary, certificates, chain, folder/'mesh', policy)
    rpc = rpc_run(binary, certificates, folder/'rpc', chain, state_policy=(1000, 1000000))
    assert rpc['passed']
    # The RPC harness mutates its input after startup; restore the complete seed before negative cases.
    chain.write_text(seed)
    base = [str(binary), 'server', '--net-port', peer_port(), '--net-cert', str(certificates/'a.cert.pem'),
            '--net-key', str(certificates/'a.key.pem'), '--net-peer-key', '-', '--net-alpn', 'jamnp-s/1/00000000', '--net-timeout-ms', '100', '--net-mode', 'valid']
    mesh_ports = ports()
    mesh_base = [str(binary), 'mesh', '--net-local-port', str(mesh_ports[0]), '--net-remote-port', str(mesh_ports[1]), '--net-cert', str(certificates/'a.cert.pem'),
                 '--net-key', str(certificates/'a.key.pem'), '--net-local-key', str(certificates/'a.pub'), '--net-peer-key', str(certificates/'b.pub'),
                 '--net-alpn', 'jamnp-s/1/00000000', '--net-gate', str(folder)]
    for command in (base, mesh_base):
        for text in ('{}', seed.replace('genesis_state', 'missing_state')):
            chain.write_text(text)
            refused = subprocess.run([*command, '--chain', str(chain), *policy], capture_output=True, timeout=5)
            assert refused.returncode == 2 and b'READY' not in refused.stdout, refused
        chain.unlink()
        missing = subprocess.run([*command, '--chain', str(chain), *policy], capture_output=True, timeout=5)
        assert missing.returncode == 2 and b'READY' not in missing.stdout, missing
        chain.write_text(seed)
        overflow = policy.copy()
        overflow[2] = '18446744073709551616'
        refused = subprocess.run([*command, '--chain', str(chain), *overflow], capture_output=True, timeout=5)
        assert refused.returncode == 2 and b'READY' not in refused.stdout, refused
    return dict(passed=True, standalone=True, retained_mesh=True, rpc=rpc,
                missing_invalid_seed_rejected=True, overflow_rejected=True)
