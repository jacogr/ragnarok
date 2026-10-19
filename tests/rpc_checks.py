# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent RFC 6455 socket checks against the actual peer executable, with no WebSocket dependency.

Exposes socket helpers and run for live protocol checks; parameter_checks verifies configured
parameters and service queries, shared telemetry startup, immutable configuration and rejected invalid inputs.
"""
import base64
import hashlib
import json
import os
import socket
import struct
import subprocess
import time
from pathlib import Path


# Read exactly one bounded wire field; premature EOF is a failed protocol exchange.
def exact(connection, size):
    result = b''
    while len(result) < size:
        part = connection.recv(size - len(result))
        assert part, 'unexpected WebSocket EOF'
        result += part
    return result


# Encode canonical client masking independently of Nim framing code.
def send(connection, payload, opcode=1, final=True):
    payload = payload.encode() if isinstance(payload, str) else payload
    prefix = bytes([(0x80 if final else 0) | opcode])
    if len(payload) < 126:
        prefix += bytes([0x80 | len(payload)])
    else:
        prefix += b'\xfe' + struct.pack('!H', len(payload))
    mask = b'\x01\x32\x54\x76'
    connection.sendall(prefix + mask + bytes(value ^ mask[i % 4] for i, value in enumerate(payload)))


# Decode a final unmasked server frame, checking lengths before reading a bounded response.
def receive(connection):
    first, second = exact(connection, 2)
    assert first & 0x80 and not second & 0x80 and not first & 0x70
    size = second & 127
    assert size != 127 # Reject the 64-bit length discriminator, not a decoded 127-byte payload.
    if size == 126:
        size, = struct.unpack('!H', exact(connection, 2))
        assert size >= 126
    assert size < 65536
    return first & 15, exact(connection, size)


# Upgrade a local socket and independently verify the server's challenge response.
def connect(port):
    connection = socket.create_connection(('127.0.0.1', port), timeout=3)
    connection.settimeout(3)
    key = base64.b64encode(b'0123456789abcdef').decode()
    header = (f'GET / HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\n'
              f'Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n')
    connection.sendall(header.encode())
    response = b''
    while not response.endswith(b'\r\n\r\n'):
        response += exact(connection, 1)
        assert len(response) <= 4096
    expected = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
    assert response.startswith(b'HTTP/1.1 101 ') and expected in response
    return connection


# Observe peer readiness with a finite deadline; early process failure remains visible in its saved log.
def ready(process, log):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        text = log.read_text()
        assert process.poll() is None, text
        if 'READY' in text.splitlines():
            return
        time.sleep(.02)
    raise AssertionError('RPC peer startup timed out: ' + log.read_text())


# Exercise RPC on a real retained peer while an independent QUIC client completes application work.
def run(binary, certificates, folder, chain=None, telemetry=False, service_queries=False):
    folder.mkdir(parents=True, exist_ok=True)
    stop = folder/'stop'
    stop.unlink(missing_ok=True)
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        rpc_port = reservation.getsockname()[1]
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(('127.0.0.1', 0))
        peer_port = reservation.getsockname()[1]
    log = folder/'peer.log'
    command = [str(binary), 'server', str(peer_port), str(certificates/'a.cert.pem'),
               str(certificates/'a.key.pem'), '-', 'jamnp-s/1/00000000', '30000', 'service',
               '--rpc-port', str(rpc_port)]
    if chain is not None:
        command += ['--chain', str(chain)] # The same CLI supports RPC with and without telemetry.
    if telemetry:
        command += ['--telemetry', '127.0.0.1:1'] # A down collector must not prevent configured RPC service.
    expected_genesis = None
    if chain is not None and 'genesis_state' in json.loads(chain.read_text()):
        # This harness uses the frozen synthetic genesis for every configured chain view.
        expected_file = 'rpc-services-result.json' if service_queries else 'rpc-genesis-result.json'
        expected_genesis = json.loads((Path(__file__).parent/'fixtures'/expected_file).read_text())
    with log.open('wb') as output:
        process = subprocess.Popen(command, env={**os.environ, 'RAGNAROK_SERVICE_STOP': str(stop)},
                                   stdout=output, stderr=subprocess.STDOUT)
        sockets = []
        try:
            ready(process, log)
            with connect(rpc_port) as connection:
                request = dict(jsonrpc='2.0', method='ragnarok_clientInfo', id='client')
                text = json.dumps(request)
                send(connection, text[:20], final=False)
                send(connection, b'probe', opcode=9)
                assert receive(connection) == (10, b'probe')
                send(connection, text[20:], opcode=0)
                opcode, payload = receive(connection)
                result = json.loads(payload)
                assert opcode == 1 and result['id'] == 'client'
                assert result['result']['rpc']['transport'] == 'websocket'
                assert result['result']['connectedPeers'] == 0
                expected_head = None if expected_genesis is None else {k: expected_genesis[k] for k in ('header_hash', 'slot')}
                assert result['result']['bestBlock'] == expected_head
                assert 'parameters' in result['result']['rpc']['methods']
                assert result['result']['rpc']['subscriptions'] is True
                assert 'subscribeBestBlock' in result['result']['rpc']['methods']
                assert 'unsubscribeBestBlock' in result['result']['rpc']['methods']
                send(connection, json.dumps(dict(jsonrpc='2.0', method='subscribeBestBlock', params=[], id=60)))
                subscribed = json.loads(receive(connection)[1])
                if expected_head is None:
                    assert subscribed['error']['code'] == 0 # No chain source means no successful subscription.
                else:
                    # Initial snapshot follows the numeric-ID response on the same live connection.
                    assert subscribed == dict(jsonrpc='2.0', id=60, result=1)
                    update = json.loads(receive(connection)[1])
                    assert update == dict(jsonrpc='2.0', method='subscribeBestBlock',
                                          params=dict(subscription=1, result=expected_head))
                    for expected in (True, False):
                        # First cancellation owns the subscription; a repeated cancellation reports absence.
                        send(connection, json.dumps(dict(jsonrpc='2.0', method='unsubscribeBestBlock', params=[1], id=61)))
                        assert json.loads(receive(connection)[1]) == dict(jsonrpc='2.0', id=61, result=expected)
                assert 'subscribeStatistics' in result['result']['rpc']['methods']
                for finalized in (True, False):
                    # Finalized tracking is unavailable; best-chain tracking requires a valid C(13) source.
                    send(connection, json.dumps(dict(jsonrpc='2.0', method='subscribeStatistics', params=[finalized], id=63)))
                    statistics_subscription = json.loads(receive(connection)[1])
                    if finalized or not service_queries:
                        assert statistics_subscription['error']['code'] == 0
                    else:
                        assert statistics_subscription == dict(jsonrpc='2.0', id=63, result=2)
                        update = json.loads(receive(connection)[1])
                        assert update == dict(jsonrpc='2.0', method='subscribeStatistics',
                                              params=dict(subscription=2, result={**expected_head, 'value': expected_genesis['statistics']}))
                        send(connection, json.dumps(dict(jsonrpc='2.0', method='unsubscribeStatistics', params=[2], id=64)))
                        assert json.loads(receive(connection)[1]) == dict(jsonrpc='2.0', id=64, result=True)
                assert 'subscribeServiceData' in result['result']['rpc']['methods']
                assert 'unsubscribeServiceData' in result['result']['rpc']['methods']
                send(connection, json.dumps(dict(jsonrpc='2.0', method='subscribeServiceData', params=[42, True], id=65)))
                assert json.loads(receive(connection)[1])['error']['code'] == 0
                send(connection, json.dumps(dict(jsonrpc='2.0', method='subscribeServiceData', params=[42, False], id=66)))
                account_subscription = json.loads(receive(connection)[1])
                if expected_head is None:
                    assert account_subscription['error']['code'] == 0 # An absent chain cannot be treated as an absent service.
                else:
                    account_id = 3 if service_queries else 2
                    assert account_subscription == dict(jsonrpc='2.0', id=66, result=account_id)
                    update = json.loads(receive(connection)[1])
                    account_value = expected_genesis['metadata'] if service_queries else None
                    assert update == dict(jsonrpc='2.0', method='subscribeServiceData',
                                          params=dict(subscription=account_id, result={**expected_head, 'value': account_value}))
                    send(connection, json.dumps(dict(jsonrpc='2.0', method='unsubscribeServiceData', params=[account_id], id=67)))
                    assert json.loads(receive(connection)[1]) == dict(jsonrpc='2.0', id=67, result=True)
                assert 'subscribeServiceValue' in result['result']['rpc']['methods']
                send(connection, json.dumps(dict(jsonrpc='2.0', method='subscribeServiceValue', params=[42, 'a2V5', True], id=68)))
                assert json.loads(receive(connection)[1])['error']['code'] == 0
                send(connection, json.dumps(dict(jsonrpc='2.0', method='subscribeServiceValue', params=[42, 'a2V5', False], id=69)))
                value_subscription = json.loads(receive(connection)[1])
                if expected_head is None:
                    assert value_subscription['error']['code'] == 0 # Missing chain state cannot be reported as a missing key.
                else:
                    value_id = 4 if service_queries else 3
                    assert value_subscription == dict(jsonrpc='2.0', id=69, result=value_id)
                    update = json.loads(receive(connection)[1])
                    stored_value = expected_genesis['value'] if service_queries else None
                    assert update == dict(jsonrpc='2.0', method='subscribeServiceValue',
                                          params=dict(subscription=value_id, result={**expected_head, 'value': stored_value}))
                    send(connection, json.dumps(dict(jsonrpc='2.0', method='unsubscribeServiceValue', params=[value_id], id=70)))
                    assert json.loads(receive(connection)[1]) == dict(jsonrpc='2.0', id=70, result=True)
                assert 'subscribeServicePreimage' in result['result']['rpc']['methods']
                preimage_hash = expected_genesis['preimage_hash'] if service_queries else 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
                send(connection, json.dumps(dict(jsonrpc='2.0', method='subscribeServicePreimage', params=[42, preimage_hash, False], id=71)))
                preimage_subscription = json.loads(receive(connection)[1])
                if expected_head is None:
                    assert preimage_subscription['error']['code'] == 0 # Missing chain cannot imply missing preimage.
                else:
                    preimage_id = 5 if service_queries else 4
                    assert preimage_subscription == dict(jsonrpc='2.0', id=71, result=preimage_id)
                    expected_preimage = expected_genesis['preimage'] if service_queries else None
                    assert json.loads(receive(connection)[1]) == dict(jsonrpc='2.0', method='subscribeServicePreimage', params=dict(subscription=preimage_id, result={**expected_head, 'value': expected_preimage}))
                    send(connection, json.dumps(dict(jsonrpc='2.0', method='unsubscribeServicePreimage', params=[preimage_id], id=72)))
                    assert json.loads(receive(connection)[1]) == dict(jsonrpc='2.0', id=72, result=True) # Cancellation releases the matching family only.
                parameter_call = dict(jsonrpc='2.0', method='parameters', params=[], id=19)
                send(connection, json.dumps(parameter_call))
                parameters = json.loads(receive(connection)[1])
                if chain is None:
                    assert parameters['error']['code'] == 0 # Missing configuration is explicit, never a default network.
                else:
                    expected = json.loads((Path(__file__).parent/'fixtures/rpc-parameters-result.json').read_text())
                    if expected_genesis is not None:
                        # Both frozen genesis fixtures contain six active validators, despite four cores.
                        expected['V1']['val_count'] = 6
                        # Six active validators give three original shards, hence 6-byte pieces.
                        expected['V1']['basic_piece_len'] = 6
                        expected['V1']['segment_piece_count'] = 684
                        # Only the service fixture has complete C(4), with nine pending validators.
                        expected['V1']['tickets_attempts_number'] = expected_genesis.get('tickets_attempts_number', 0)
                    assert parameters == dict(jsonrpc='2.0', id=19, result=expected)
                    # File changes after startup cannot change the node's immutable parameter snapshot.
                    chain.write_text('{}')
                    send(connection, json.dumps(parameter_call))
                    assert json.loads(receive(connection)[1]) == parameters
                    send(connection, json.dumps([parameter_call] * 16))
                    assert json.loads(receive(connection)[1]) == [parameters] * 16
                send(connection, json.dumps(dict(parameter_call, params=[1])))
                assert json.loads(receive(connection)[1])['error']['code'] == -32602

                # A notification contributes no response; the next identified call must be received first.
                send(connection, json.dumps(dict(jsonrpc='2.0', method='ragnarok_clientInfo')))
                send(connection, json.dumps([request, dict(jsonrpc='2.0', method='bestBlock', id=2), False]))
                response = json.loads(receive(connection)[1])
                assert len(response) == 3
                if expected_head is None:
                    assert response[1]['error']['code'] == 0 # No configured genesis head.
                else:
                    assert response[1]['result'] == expected_head # File mutation did not change the retained chain.
                    query = dict(jsonrpc='2.0', method='stateRoot', params=[expected_head['header_hash']], id=3)
                    send(connection, json.dumps(query))
                    assert json.loads(receive(connection)[1])['result'] == expected_genesis['state_root']
                    # Exact retained header bytes still hash to the advertised identity after source mutation.
                    send(connection, json.dumps(dict(query, method='ragnarok_header')))
                    header_reply = json.loads(receive(connection)[1])
                    raw_header = base64.b64decode(header_reply['result'], validate=True)
                    assert header_reply['id'] == 3 and len(raw_header) == 297
                    assert base64.b64encode(hashlib.blake2b(raw_header, digest_size=32).digest()).decode() == expected_head['header_hash']
                    send(connection, json.dumps(dict(query, method='parent')))
                    assert json.loads(receive(connection)[1])['error'] == dict(code=1, message='Block unavailable', data=expected_head['header_hash'])
                    send(connection, json.dumps(dict(query, params=['not a hash'])))
                    assert json.loads(receive(connection)[1])['error']['code'] == -32602
                if service_queries:
                    # Exercise service payloads after source-file mutation, on the same retained connection.
                    check_service_queries(connection, expected_genesis)
                assert response[2]['error']['code'] == -32600
                send(connection, '{broken')
                assert json.loads(receive(connection)[1])['error']['code'] == -32700
                # Valid QUIC traffic must progress while RPC is connected and usable.
                clients = []
                try:
                    # The retained service's existing proof contract requires three concurrent peers.
                    for identity in ('b', 'c', 'd'):
                        clients.append(subprocess.Popen([str(binary), 'client', str(peer_port),
                                       str(certificates/f'{identity}.cert.pem'), str(certificates/f'{identity}.key.pem'),
                                       str(certificates/'a.pub'), 'jamnp-s/1/00000000', '5000', 'mixed'],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE))
                    for client in clients:
                        stdout, stderr = client.communicate(timeout=8)
                        assert client.returncode == 0, stdout + stderr
                finally:
                    # Concurrent clients are reaped on every protocol/assertion failure.
                    for client in clients:
                        if client.poll() is None:
                            client.kill()
                        client.wait(timeout=5)
                send(connection, text)
                assert json.loads(receive(connection)[1])['result']['uptimeMs'] > 0
                send(connection, struct.pack('!H', 1000), opcode=8)
                assert receive(connection) == (8, struct.pack('!H', 1000))
                assert connection.recv(1) == b''
            # Every unmasked client data frame receives a protocol close, not a JSON result.
            with connect(rpc_port) as connection:
                connection.sendall(b'\x81\x02{}')
                assert receive(connection) == (8, struct.pack('!H', 1002))
            # POST is never a second RPC transport.
            with socket.create_connection(('127.0.0.1', rpc_port), timeout=3) as connection:
                connection.sendall(b'POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2\r\n\r\n{}')
                assert connection.recv(1) == b''
            # Saturated idle handshakes expire; a fresh client can then use the same listener.
            for _ in range(8):
                sockets.append(socket.create_connection(('127.0.0.1', rpc_port), timeout=3))
            time.sleep(5.3)
            for connection in sockets:
                connection.settimeout(2)
                assert connection.recv(1) == b''
            with connect(rpc_port) as connection:
                send(connection, text)
                assert json.loads(receive(connection)[1])['id'] == 'client'
            stop.touch()
            assert process.wait(timeout=5) == 0, log.read_text()
            assert 'SERVICE_CLEAN' in log.read_text()
        finally:
            # Failures close client descriptors and reap the native process rather than leaving a live listener.
            for connection in sockets:
                connection.close()
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
    return dict(passed=True, transport='websocket', quic_progress=True, bounded_admission=True,
                clean_shutdown=True, log=str(log))


# Query frozen service fixtures and prove that large batches remain bounded without losing response IDs.
def check_service_queries(connection, expected):
    header = expected['header_hash']
    cases = [
        ('statistics', [header], expected['statistics']),
        ('ragnarok_stateValue', [header, 'CwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=='], 'BwAAAA=='),
        ('ragnarok_stateValue', [header, '/wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=='], None),
        ('beefyRoot', [header], expected['beefy_root']),
        ('workReport', [expected['work_report_hash']], expected['work_report']),
        ('workReport', [expected['ready_report_hash']], expected['ready_report']),
        ('listServices', [header], [42, 4294967295]),
        ('serviceRequest', [header, 42, 'A'*43+'=', 0], []),
        ('serviceRequest', [header, 42, 'A'*43+'=', 1], [0]),
        ('serviceRequest', [header, 42, 'A'*43+'=', 2], [1, 4294967295]),
        ('serviceRequest', [header, 42, 'A'*43+'=', 3], [0, 2147483648, 4294967295]),
        ('serviceRequest', [header, 42, 'A'*43+'=', 9], None),
        ('serviceRequest', [header, 42, 'A'*43+'=', 4294967293], []),
        ('serviceData', [header, 42], expected['metadata']),
        ('serviceValue', [header, 42, 'a2V5'], expected['value']),
        ('serviceValue', [header, 42, ''], ''),
        ('serviceValue', [header, 42, 'bm9uZQ=='], None),
        ('serviceData', [header, 41], None),
        ('servicePreimage', [header, 42, expected['preimage_hash']], expected['preimage']),
        ('servicePreimage', [header, 42, expected['empty_preimage_hash']], ''),
    ]
    for index, (method, params, result) in enumerate(cases):
        # Compare the complete decoded JSON envelope, keeping null distinct from an empty Base64 string.
        send(connection, json.dumps(dict(jsonrpc='2.0', method=method, params=params, id=index)))
        assert json.loads(receive(connection)[1]) == dict(jsonrpc='2.0', id=index, result=result)
    # Traverse exact independent fixture keys across small pages after startup source mutation.
    collected = []
    cursor = None
    for page in range(len(expected['state_keys']) + 1):
        # This fixed upper bound prevents a broken continuation cursor from hanging the harness.
        query = dict(jsonrpc='2.0', method='ragnarok_stateKeys', params=[header, cursor, 5], id=900)
        send(connection, json.dumps(query))
        response = json.loads(receive(connection)[1])
        assert response['id'] == 900 and 'result' in response
        result = response['result']
        assert len(result['keys']) <= 5
        collected.extend(result['keys'])
        cursor = result['next']
        if cursor is None:
            break # Complete traversal has an explicit terminal cursor even on an exact final page.
        assert result['keys'] and cursor == result['keys'][-1]
    assert cursor is None and collected == expected['state_keys']
    for length in (4, 5, 6, 4294967294, 4294967295):
        # Malformed histories and present colliding namespaces are explicit errors on the live transport too.
        send(connection, json.dumps(dict(jsonrpc='2.0', method='serviceRequest', params=[header, 42, 'A'*43+'=', length], id=90)))
        assert json.loads(receive(connection)[1])['error']['code'] == 0
    large = dict(jsonrpc='2.0', method='serviceValue', params=[header, 42, 'bGFyZ2U='], id=100)
    send(connection, json.dumps(large))
    assert base64.b64decode(json.loads(receive(connection)[1])['result']) == b'x' * 32768
    send(connection, json.dumps(dict(large, params=[header, 42, 'b3ZlcnNpemU='])))
    assert json.loads(receive(connection)[1])['error']['code'] == 0
    batch = [dict(large, id='\n' * 200 + str(index)) for index in range(16)]
    send(connection, json.dumps(batch))
    opcode, payload = receive(connection)
    replies = json.loads(payload)
    assert opcode == 1 and len(payload) <= 65535 and len(replies) == 16
    assert [reply['id'] for reply in replies] == [request['id'] for request in batch]
    assert any('result' in reply for reply in replies) and any('error' in reply for reply in replies)
    for reply in replies:
        # Capacity failures are explicit per-request errors; successful values are complete, never truncated.
        if 'error' in reply:
            assert reply['error']['code'] == 0
        else:
            assert base64.b64decode(reply['result']) == b'x' * 32768
    send(connection, json.dumps(dict(large, method='serviceData', params=[header, 42])))
    assert json.loads(receive(connection)[1])['result'] == expected['metadata']


# Run configured and unconfigured startup, then prove explicitly malformed chains fail before serving.
def parameter_checks(binary, certificates, folder):
    folder.mkdir(parents=True, exist_ok=True)
    chain = folder/'chain.json'
    chain.write_text((Path(__file__).parent/'fixtures/rpc-parameters.json').read_text())
    result = run(binary, certificates, folder/'configured', chain)
    # The independent synthetic genesis supports queries and shared telemetry startup.
    combined = json.loads((Path(__file__).parent/'fixtures/rpc-genesis.json').read_text())
    chain.write_text(json.dumps(combined))
    shared = run(binary, certificates, folder/'shared', chain, telemetry=True)
    assert shared['passed']
    # A separate explicit map supplies metadata, storage and preimages without altering genesis fixtures.
    chain.write_text((Path(__file__).parent/'fixtures/rpc-services.json').read_text())
    services = run(binary, certificates, folder/'services', chain, service_queries=True)
    assert services['passed']
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        rpc_port = reservation.getsockname()[1]
    # The preceding run changed its source file to {}; startup must now reject that incomplete configuration.
    arguments = [str(binary), 'server', '19899', str(certificates/'a.cert.pem'),
                 str(certificates/'a.key.pem'), '-', 'jamnp-s/1/00000000', '100', 'valid',
                 '--rpc-port', str(rpc_port), '--chain', str(chain)]
    failed = subprocess.run(arguments, capture_output=True, timeout=5)
    assert failed.returncode != 0 and b'Invalid RPC listener or --chain parameters' in failed.stderr
    # Supplied genesis fields must form a complete valid pair before a listener can open.
    for malformed in (dict(combined, genesis_state={}), dict(combined, genesis_header='00'),
                      {key: value for key, value in combined.items() if key != 'genesis_state'}):
        chain.write_text(json.dumps(malformed))
        rejected = subprocess.run(arguments, capture_output=True, timeout=5)
        assert rejected.returncode != 0 and b'Invalid RPC listener or --chain parameters' in rejected.stderr
    chain.unlink()
    missing = subprocess.run(arguments, capture_output=True, timeout=5)
    assert missing.returncode != 0 and b'Invalid RPC listener or --chain parameters' in missing.stderr
    return dict(passed=result['passed'], immutable_configuration=True, invalid_startup_rejected=True, service_queries=True)
