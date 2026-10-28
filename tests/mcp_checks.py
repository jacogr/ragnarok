# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exercise MCP lifecycle and chain reads through the real application process.

The native suites own parser/query assertions; this workload owns CLI, HTTP client and process cleanup.
"""
import http.client
import json
import os
from pathlib import Path
import socket
import subprocess

from rpc_checks import ready


# Reserve explicit ephemeral TCP/UDP ports without guessing globally unused values.
def free_port(kind=socket.SOCK_STREAM):
    with socket.socket(socket.AF_INET, kind) as reservation:
        reservation.bind(('127.0.0.1', 0))
        return reservation.getsockname()[1]


# A fresh connection per message verifies stateless MCP clients can reconnect after initialization.
def exchange(port, message):
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=3)
    try:
        body = json.dumps(message).encode()
        connection.request('POST', '/mcp', body, headers={
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            'MCP-Protocol-Version': '2025-11-25',
        })
        reply = connection.getresponse()
        data = reply.read(131073)
        assert len(data) <= 131072, 'MCP response exceeded its declared budget'
        assert reply.status == (200 if 'id' in message else 202)
        return json.loads(data) if data else None
    finally:
        connection.close()


# Bounded process lifetime and isolated stop/log paths keep failed startup or requests reviewable.
def run(binary, certificates, folder):
    folder.mkdir(parents=True, exist_ok=True)
    port = free_port()
    peer_port = free_port(socket.SOCK_DGRAM)
    stop = folder/'stop'
    stop.unlink(missing_ok=True)
    log = folder/'peer.log'
    root = Path(__file__).resolve().parents[1]
    command = [str(binary), 'server', '--net-port', str(peer_port),
               '--net-cert', str(certificates/'a.cert.pem'), '--net-key', str(certificates/'a.key.pem'),
               '--net-peer-key', '-', '--net-alpn', 'jamnp-s/1/00000000', '--net-timeout-ms', '30000',
               '--net-mode', 'service', '--with-mcp', '--mcp-port', str(port),
               '--chain', str(root/'tests/fixtures/rpc-genesis.json')]
    with log.open('wb') as output:
        process = subprocess.Popen(command, env={**os.environ, 'RAGNAROK_SERVICE_STOP': str(stop)},
                                   stdout=output, stderr=subprocess.STDOUT, cwd=folder)
        try:
            ready(process, log)
            initialized = exchange(port, dict(jsonrpc='2.0', id=1, method='initialize', params=dict(
                protocolVersion='2025-11-25', capabilities={}, clientInfo=dict(name='e2e', version='1'))))
            assert initialized['result']['protocolVersion'] == '2025-11-25'
            exchange(port, dict(jsonrpc='2.0', method='notifications/initialized'))
            catalog = exchange(port, dict(jsonrpc='2.0', id=2, method='tools/list'))
            assert {entry['name'] for entry in catalog['result']['tools']} == {
                'get_chain_status', 'get_parameters', 'get_block', 'list_services',
                'get_service', 'get_storage', 'get_preimage'}
            status = exchange(port, dict(jsonrpc='2.0', id=3, method='tools/call', params=dict(
                name='get_chain_status', arguments={})))['result']
            assert status['isError'] is False
            chain = status['structuredContent']
            expected = json.loads((root/'tests/fixtures/rpc-genesis-result.json').read_text())
            assert chain['nodeMode'] == 'full'
            assert chain['bestBlock'] == dict(header_hash=expected['header_hash'], slot=str(expected['slot']))
            assert chain['finalizedBlock'] is None
            state = exchange(port, dict(jsonrpc='2.0', id=4, method='tools/call', params=dict(
                name='get_block', arguments=dict(block_hash=expected['header_hash']))))['result']
            assert state['isError'] is False and state['structuredContent']['value'] == expected['state_root']
            assert json.loads(state['content'][0]['text']) == state['structuredContent']
            stop.touch()
            # With no QUIC workload the proof peer deliberately exits 2 after clean service teardown.
            assert process.wait(timeout=5) == 2, log.read_text()
            assert 'SERVICE_DONE 0 0 0' in log.read_text()
            return dict(passed=True, protocol='2025-11-25', tools=7, log=str(log))
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
