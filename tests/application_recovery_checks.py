# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify explicit checkpoint imports through the actual executable and independent RPC wire client.

Exposes run for the E2E plan; fixtures are hash-checked before independent header/context
variants are authored. Every child is bounded and reaped, with logs under the supplied build path.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
from application_state_checks import peer_port
from rpc_checks import connect, send, receive, ready
from test_quic_mesh import ports


# Read committed bytes only after their existing fixture descriptor agrees with the exact digest.
def pinned(name):
    folder = Path(__file__).parent/'fixtures'
    descriptor = json.loads((folder/(name+'.fixture.json')).read_text())
    for member, digest in descriptor['files'].items():
        # The descriptor supplies immutable independent fixture identity, not recovery authority.
        assert hashlib.sha256((folder/member).read_bytes()).hexdigest() == digest, member
    return (folder/descriptor['target']).read_bytes()


# Produce a separately selected operator anchor whose sealed identity differs from configured genesis.
def inputs(folder):
    folder.mkdir(parents=True, exist_ok=True)
    chain = pinned('application_checkpoint')
    metadata = bytearray(pinned('application_checkpoint_identity'))
    envelope = pinned('application_checkpoint_bundle')
    assert len(metadata) == 238 and envelope[:238] == metadata
    wire = bytearray.fromhex(json.loads(chain)['genesis_header'])
    wire[-1] ^= 1
    metadata[16:48] = hashlib.blake2b(wire, digest_size=32).digest()
    metadata[206:] = hashlib.blake2b(metadata[:206], digest_size=32).digest()
    selected = {'chain': chain, 'identity': bytes(metadata), 'header': bytes(wire),
                'checkpoint': bytes(metadata)+envelope[238:]}
    paths = {key: folder/(key+'.bin') for key in selected}
    for key, data in selected.items():
        # Trusted metadata/header paths remain independent of the checkpoint path throughout each process.
        paths[key].write_bytes(data)
    return paths, selected


# Build exactly the documented atomic import group and existing complete-state mutation policy.
def policy(paths, limit):
    return ['--with-state', '--chain', str(paths['chain']), '--state-writes', '0',
            '--state-write-bytes', '0', '--state-checkpoint', str(paths['checkpoint']),
            '--state-trust', str(paths['identity']), '--state-header', str(paths['header']),
            '--state-checkpoint-bytes', str(limit)]


# A real retained peer must expose the imported head, exact sealed bytes and unset finality.
def serving(binary, certificates, folder, paths, selected):
    folder.mkdir(parents=True, exist_ok=True)
    stop, log = folder/'stop', folder/'peer.log'
    stop.unlink(missing_ok=True)
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        rpc_port = reservation.getsockname()[1]
    command = [str(binary), 'server', '--net-port', peer_port(), '--net-cert', str(certificates/'a.cert.pem'),
               '--net-key', str(certificates/'a.key.pem'), '--net-peer-key', '-', '--net-alpn', 'jamnp-s/1/00000000', '--net-timeout-ms', '30000', '--net-mode', 'service',
               *policy(paths, len(selected['checkpoint'])), '--with-rpc', '--rpc-port', str(rpc_port)]
    with log.open('wb') as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                                   env={**os.environ, 'RAGNAROK_SERVICE_STOP': str(stop)})
        try:
            ready(process, log)
            expected_hash = base64.b64encode(selected['identity'][16:48]).decode()
            expected_root = base64.b64encode(selected['identity'][48:80]).decode()
            with connect(rpc_port) as connection:
                def query(method, params=None):
                    """Send independent JSON-RPC framing and require exact request identity in its response."""
                    request = dict(jsonrpc='2.0', method=method, id=1)
                    if params is not None:
                        # Omitted/no-argument methods and explicit hash lookups remain distinct requests.
                        request['params'] = params
                    send(connection, json.dumps(request))
                    response = json.loads(receive(connection)[1])
                    assert response['id'] == 1
                    return response
                best = query('bestBlock')['result']
                assert best['header_hash'] == expected_hash
                assert best['slot'] == int.from_bytes(selected['identity'][80:84], 'little')
                assert query('stateRoot', [expected_hash])['result'] == expected_root
                sealed = query('ragnarok_header', [expected_hash])['result']
                assert base64.b64decode(sealed, validate=True) == selected['header']
                assert query('finalizedBlock')['error']['message'] == 'Finalized chain view unavailable'
                assert query('parent', [expected_hash])['error']['code'] == 1
            stop.touch()
            assert process.wait(timeout=5) == 2, log.read_text()
            assert 'SERVICE_DONE 0 0 0' in log.read_text()
        finally:
            # Every success, failed query or timeout retires and reaps the actual application process.
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
    return dict(passed=True, header_hash=expected_hash, state_root=expected_root,
                finality_unset=True, exact_sealed_header=True)


# Refusals must occur before readiness in both executable peer shapes and preserve all input bytes.
def refusals(binary, certificates, folder, paths, selected):
    folder.mkdir(parents=True, exist_ok=True)
    server = [str(binary), 'server', '--net-port', peer_port(), '--net-cert', str(certificates/'a.cert.pem'),
              '--net-key', str(certificates/'a.key.pem'), '--net-peer-key', '-', '--net-alpn', 'jamnp-s/1/00000000', '--net-timeout-ms', '100', '--net-mode', 'valid']
    mesh_ports = ports()
    mesh = [str(binary), 'mesh', '--net-local-port', str(mesh_ports[0]), '--net-remote-port', str(mesh_ports[1]), '--net-cert', str(certificates/'a.cert.pem'),
            '--net-key', str(certificates/'a.key.pem'), '--net-local-key', str(certificates/'a.pub'), '--net-peer-key', str(certificates/'b.pub'),
            '--net-alpn', 'jamnp-s/1/00000000', '--net-gate', str(folder)]
    rows = []
    cases = [('zero-budget', None, None, 0), ('short-budget', None, None, len(selected['checkpoint'])-1)]
    for key in ('identity', 'header', 'checkpoint'):
        # Missing each selected path must not select another file or configured genesis instead.
        cases.append(('missing-'+key, key, None, len(selected['checkpoint'])))
    cases.extend([('bad-identity', 'identity', b'bad', len(selected['checkpoint'])),
                  ('bad-header', 'header', b'bad', len(selected['checkpoint'])),
                  ('bad-checkpoint', 'checkpoint', b'bad', len(selected['checkpoint']))])
    for shape, command in [('server', server), ('mesh', mesh)]:
        for name, key, replacement, limit in cases:
            # Restore independent baseline inputs before selecting exactly one native/format/policy refusal.
            for member, data in selected.items():
                paths[member].write_bytes(data)
            if key is not None:
                if replacement is None:
                    paths[key].unlink() # An absent selected file must refuse rather than trigger fallback.
                else:
                    paths[key].write_bytes(replacement) # Existing malformed files must also remain untouched.
            before = {member: path.read_bytes() if path.exists() else None for member, path in paths.items()}
            result = subprocess.run([*command, *policy(paths, limit)], capture_output=True, timeout=5)
            (folder/(shape+'-'+name+'.log')).write_bytes(result.stdout+result.stderr)
            assert result.returncode == 2 and b'READY' not in result.stdout, (shape, name, result)
            after = {member: path.read_bytes() if path.exists() else None for member, path in paths.items()}
            assert after == before, (shape, name, 'startup modified independent input files')
            rows.append(dict(shape=shape, case=name, passed=True))
    for member, data in selected.items():
        paths[member].write_bytes(data) # Leave deterministic input fixtures for later focused diagnostics.
    return rows


# The E2E plan owns build/setup; direct selected runs must supply that same prepared binary/certificate context.
def run(binary, certificates, folder):
    paths, selected = inputs(folder/'inputs')
    help_text = subprocess.run([str(binary), '--help'], capture_output=True, check=True, timeout=5).stdout
    for control in ('--state-checkpoint', '--state-trust', '--state-header', '--state-checkpoint-bytes'):
        assert control.encode() in help_text
    positive = serving(binary, certificates, folder/'serving', paths, selected)
    negative = refusals(binary, certificates, folder/'refusals', paths, selected)
    return dict(passed=positive['passed'] and all(row['passed'] for row in negative),
                serving=positive, refusals=negative)
