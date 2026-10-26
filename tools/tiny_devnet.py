#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Launch six native Tiny validators with public development keys and bounded cleanup.

Python owns certificates and processes only. The native executable constructs genesis,
authors, transports, validates, executes and journals every block. Optional test callbacks
freeze independent expectations before nodes start and inspect observations after shutdown.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT/'config/tiny-devnet-policy.conf'


def command(arguments, *, timeout=20):
    """Run one bounded prerequisite without shell expansion or hidden failure status."""
    return subprocess.run([str(value) for value in arguments], check=True,
                          capture_output=True, text=True, timeout=timeout).stdout


def certificates(binary, directory):
    """Use native JIP-5 development PKCS8 exports; the same native identity supplies each SAN."""
    openssl = shutil.which('openssl')
    if openssl is None:
        raise RuntimeError('OpenSSL is required for local TLS certificates')
    for index in range(6):
        folder = directory/f'node-{index}'
        folder.mkdir()
        identity = json.loads(command([binary, 'tiny-devnet', 'identity', index]))
        der = folder/'key.der'
        der.write_bytes(bytes.fromhex(identity['pkcs8']))
        der.chmod(0o600)
        key = folder/'key.pem'
        command([openssl, 'pkey', '-inform', 'DER', '-in', der, '-out', key])
        key.chmod(0o600)
        public = subprocess.check_output([openssl, 'pkey', '-in', key, '-pubout', '-outform', 'DER'])
        if public != bytes.fromhex('302a300506032b6570032100')+bytes.fromhex(identity['public']):
            raise RuntimeError('OpenSSL/native development identity mismatch')
        san = identity['name'].replace('$', r'\$')
        command([openssl, 'req', '-new', '-x509', '-key', key, '-out', folder/'cert.pem',
                 '-days', '2', '-subj', '/CN=ragnarok-tiny-devnet',
                 '-addext', 'subjectAltName=DNS:'+san])
        der.unlink() # The retained PEM is the single process-owned TLS key file.


def free_ports():
    """Reserve and release six contiguous loopback UDP ports with a finite admission budget."""
    for _ in range(100):
        sockets = []
        try:
            first = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sockets.append(first)
            first.bind(('127.0.0.1', 0))
            base = first.getsockname()[1]
            if base > 65530:
                continue # A complete six-port range must fit the native uint16 endpoint domain.
            for index in range(1, 6):
                current = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                sockets.append(current)
                current.bind(('127.0.0.1', base+index))
            return base
        except OSError:
            pass # Another local listener may own a sibling; retry an unrelated OS-selected base.
        finally:
            for current in sockets:
                current.close()
    raise RuntimeError('Could not reserve six contiguous loopback UDP ports')


def head(directory, index):
    """Read one atomically published observation; absence during startup is explicitly pending."""
    path = directory/f'node-{index}'/'head.json'
    return json.loads(path.read_text()) if path.exists() else None


def exercise(binary, directory, *, slots=14, restart=False, before_start=None, after_stop=None,
             progress=print):
    """Run a finite uncontested chain and require all six actual process exits and canonical heads."""
    if not 2 <= slots <= 64:
        raise ValueError('Tiny devnet needs2..64 slots')
    if restart and slots < 13:
        raise ValueError('Epoch/restart acceptance needs at least13 slots')
    binary, directory = Path(binary).resolve(), Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=False)
    certificates(binary, directory)
    command([binary, 'tiny-devnet', 'init', directory/'chain.json'])
    # Native initialization supplies a recorded genesis input, never an observed STF successor.
    expected = before_start(directory, slots) if before_start else None
    base = free_ports()
    start = int(time.time()*1000)+4000
    deadline = time.monotonic()+slots*6+35
    processes, logs, launches = {}, {}, []
    stopped, restarted = False, False
    last_report = -1

    def launch(index):
        """Each validator has independent native chain/journal resources and append-only retained logs."""
        stdout = (directory/f'node-{index}'/'stdout.log').open('ab')
        try:
            stderr = (directory/f'node-{index}'/'stderr.log').open('ab')
        except BaseException:
            stdout.close() # A failed second acquisition must still retire the first log owner.
            raise
        logs[index] = (stdout, stderr)
        arguments = [str(binary), 'tiny-devnet', 'node', str(directory), str(index),
                     str(base), str(start), str(slots), str(POLICY)]
        processes[index] = subprocess.Popen(arguments, cwd=ROOT, stdout=stdout, stderr=stderr)
        launches.append(dict(node=index, pid=processes[index].pid, command=arguments))

    try:
        for index in range(6):
            launch(index)
        while time.monotonic() < deadline:
            for index, process in processes.items():
                if process.poll() is not None and not (restart and index == 5 and stopped and not restarted):
                    raise RuntimeError(f'Node{index} exited early with{process.returncode}; see {directory}')
            heads = [head(directory, index) for index in range(6)]
            # Stop after node5's first authored slot and restart before its next first-epoch assignment.
            if restart and not stopped and all(value and value['slot'] >= 5 for value in heads):
                processes[5].terminate()
                processes[5].wait(timeout=5)
                for output in logs[5]:
                    output.close()
                stopped = True
                progress('Stopped node5 after slot5; its durable journal is retained.')
            if restart and stopped and not restarted and all(heads[index] and heads[index]['slot'] >= 8 for index in range(5)):
                launch(5)
                restarted = True
                progress('Restarted node5; it must replay and fetch its missing canonical children.')
            if all(value for value in heads):
                minimum = min(value['slot'] for value in heads)
                if minimum != last_report:
                    last_report = minimum
                    progress(f'Six-node progress: minimum slot={minimum}, maximum slot={max(value["slot"] for value in heads)}')
                if all(value['slot'] == slots for value in heads):
                    if len({(value['hash'], value['root']) for value in heads}) != 1:
                        raise RuntimeError('Six nodes reached the target with different canonical heads')
                    break
            time.sleep(0.05) # Bounded orchestration polling performs no client protocol or state execution.
        else:
            raise TimeoutError(f'Six-node convergence deadline; see {directory}')
        (directory/'STOP').write_text('stop\n')
        for index, process in processes.items():
            if process.wait(timeout=10) != 0:
                raise RuntimeError(f'Node{index} did not complete cleanly')
        if restart and not restarted:
            raise RuntimeError('Requested restart witness was not exercised')
        authors = []
        for index in range(6):
            output = (directory/f'node-{index}'/'stdout.log').read_text()
            if f'DEVNET_COMPLETE node={index}' not in output.splitlines() or 'source=peer' not in output:
                raise RuntimeError(f'Node{index} lacks remote adoption or clean completion evidence')
            if 'source=local' in output:
                authors.append(index) # Short runs activate only the eligible signers, while all six nodes validate every child.
        if len(authors) < min(slots,6):
            raise RuntimeError('Missing eligible development author evidence')
        checks = after_stop(directory, slots, expected) if after_stop else {}
        result = dict(passed=True, nodes=6, slots=slots, epoch_crossed=slots >= 12, authors=authors,
                      directory=str(directory), binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                      policy_sha256=hashlib.sha256(POLICY.read_bytes()).hexdigest(),
                      restart=restarted, head=heads[0], launches=launches, checks=checks)
        (directory/'result.json').write_text(json.dumps(result, indent=2)+'\n')
        progress(f'Six nodes converged at slot{slots}: {heads[0]["hash"]}, state {heads[0]["root"]}')
        return result
    finally:
        # Failure and interruption paths reap every process and retire every opened log descriptor.
        for process in processes.values():
            if process.poll() is None:
                process.terminate()
        for process in processes.values():
            if process.poll() is None:
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        for pair in logs.values():
            for output in pair:
                output.close()


def main():
    """Make owns compilation; direct use can select an already built native executable."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, default=ROOT/'build/ragnarok')
    parser.add_argument('--directory', type=Path)
    parser.add_argument('--slots', type=int, default=14)
    parser.add_argument('--restart', action='store_true')
    args = parser.parse_args()
    directory = args.directory or ROOT/'build/tiny-devnet'/time.strftime('%Y%m%d-%H%M%S')
    exercise(args.binary, directory, slots=args.slots, restart=args.restart)


if __name__ == '__main__':
    main()
