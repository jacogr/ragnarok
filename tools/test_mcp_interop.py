#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exchange real MCP messages between the pinned official SDK and the built Ragnarök peer.

Make owns SDK provisioning and compilation. This optional E2E gate owns bounded process/client
lifetimes, independent fixture checks and recorded HTTP/JSON-RPC messages; no SDK internals are patched.
"""
import argparse
import asyncio
import base64
from datetime import timedelta
import hashlib
from importlib.metadata import version
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import traceback

ROOT = Path(__file__).resolve().parents[1]
CI_GROUP = 'mcp'
SDK_VERSION = '1.26.0'
PROTOCOL = '2025-11-25'
CASES = ('configured', 'canonical', 'unconfigured')
TOOLS = {'get_chain_status', 'get_parameters', 'get_block', 'list_services',
         'get_service', 'get_storage', 'get_preimage'}


class WireRecorder:
    """Record bounded actual SDK HTTP traffic through public HTTPX hooks, without rewriting it."""

    def __init__(self, path):
        self.path = path
        self.events = []
        self.path.write_text('')

    def append(self, event):
        """Write immediately so failed sessions retain the messages preceding their failure."""
        if len(self.events) >= 256:
            raise ValueError('MCP interop message budget exceeded')
        self.events.append(event)
        with self.path.open('a') as output:
            output.write(json.dumps(event, ensure_ascii=False) + '\n')

    async def request(self, request):
        """Observe SDK serialization, method/ID and negotiated headers before real socket IO."""
        body = await request.aread()
        assert len(body) <= 16384, 'SDK request exceeds server input budget'
        self.append(dict(direction='request', method=request.method, path=request.url.path,
                         headers={key: request.headers[key] for key in
                                  ('accept', 'content-type', 'mcp-protocol-version', 'mcp-session-id')
                                  if key in request.headers},
                         message=json.loads(body) if body else None))

    async def response(self, response):
        """Check declared bounds before buffering the JSON-only peer response for both SDK and trace."""
        assert 'transfer-encoding' not in response.headers
        length = response.headers.get('content-length', '')
        assert length.isascii() and length.isdecimal() and len(length) <= 6
        assert int(length) <= 131072, 'Server response exceeds declared MCP budget'
        body = await response.aread()
        assert len(body) == int(length)
        self.append(dict(direction='response', status=response.status_code,
                         method=response.request.method,
                         headers={key: response.headers[key] for key in
                                  ('content-type', 'connection', 'mcp-session-id')
                                  if key in response.headers},
                         message=json.loads(body) if body else None))


def verify_trace(events):
    """Require actual initialize/notification/discovery/query/error traffic with correlated IDs."""
    requests = [event for event in events if event['direction'] == 'request']
    messages = [event['message'] for event in requests if event['method'] == 'POST']
    assert {'initialize', 'notifications/initialized', 'ping', 'tools/list', 'tools/call'} <= {
        message['method'] for message in messages}
    assert messages[0]['method'] == 'initialize'
    for event in requests:
        # Initialization negotiates the revision; all later SDK POSTs must carry that negotiated value.
        if event['method'] == 'POST' and event['message']['method'] != 'initialize':
            assert event['headers']['mcp-protocol-version'] == PROTOCOL
        assert 'mcp-session-id' not in event['headers'], 'Stateless server issued a session'
    request_ids = [message['id'] for message in messages if 'id' in message]
    replies = [event['message'] for event in events if event['direction'] == 'response'
               and event['method'] == 'POST' and event['status'] == 200]
    assert len(request_ids) == len(set(request_ids))
    assert set(request_ids) == {message['id'] for message in replies}
    assert len(request_ids) == len(replies), 'Lost or duplicated SDK reply'
    responses = [event for event in events if event['direction'] == 'response']
    assert any(event['status'] == 202 for event in responses), 'Initialized notification was not acknowledged'
    assert all(event['status'] == 405 for event in responses if event['method'] == 'GET')
    assert all('mcp-session-id' not in event['headers'] for event in responses)
    return dict(requests=len(messages), replies=len(replies),
                tool_calls=sum(message['method'] == 'tools/call' for message in messages))


def structured(result, *, failed=False):
    """Require SDK-parsed structured/text agreement and the expected tool error classification."""
    assert result.isError is failed
    assert isinstance(result.structuredContent, dict)
    assert len(result.content) == 1 and result.content[0].type == 'text'
    assert json.loads(result.content[0].text) == result.structuredContent
    return result.structuredContent


async def sdk_session(port, folder, index, expected):
    """The unmodified official SDK owns lifecycle, schemas, JSON-RPC IDs and real HTTP transport."""
    import httpx
    import jsonschema
    from mcp import ClientSession, types
    from mcp.client.streamable_http import streamable_http_client
    from mcp.shared.exceptions import McpError

    recorder = WireRecorder(folder/f'session-{index}.jsonl')
    async with asyncio.timeout(15):
        async with httpx.AsyncClient(timeout=3, trust_env=False,
                                     event_hooks={'request': [recorder.request],
                                                  'response': [recorder.response]}) as client:
            async with streamable_http_client(f'http://127.0.0.1:{port}/mcp', http_client=client) as streams:
                async with ClientSession(streams[0], streams[1], read_timeout_seconds=timedelta(seconds=3),
                                         client_info=types.Implementation(name='ragnarok-interop',
                                                                          version=SDK_VERSION)) as session:
                    initialized = await session.initialize()
                    assert initialized.protocolVersion == PROTOCOL
                    assert initialized.serverInfo.name == 'ragnarok'
                    assert initialized.capabilities.tools is not None
                    assert initialized.capabilities.tools.listChanged is False
                    assert streams[2]() is None, 'SDK unexpectedly acquired a session ID'
                    await session.send_ping()
                    listing = await session.list_tools()
                    assert listing.nextCursor is None
                    assert {tool.name for tool in listing.tools} == TOOLS
                    # Standard request metadata must not be mistaken for an unsupported page cursor.
                    for metadata in ({}, {'progressToken': 'discovery-1'}, {'progressToken': 7}):
                        discovered = await session.list_tools(params=types.PaginatedRequestParams(_meta=metadata))
                        assert discovered == listing
                    try:
                        # A fixed catalog still rejects actual pagination, even alongside valid metadata.
                        await session.list_tools(params=types.PaginatedRequestParams(
                            cursor='invalid', _meta={'progressToken': 'invalid-page'}))
                    except McpError as error:
                        assert error.error.code == -32602
                    else:
                        raise AssertionError('Unexpected cursor accepted')
                    for tool in listing.tools:
                        # The SDK models validate envelopes; independently validate the advertised JSON Schemas too.
                        assert tool.annotations.readOnlyHint is True
                        jsonschema.Draft202012Validator.check_schema(tool.inputSchema)
                        jsonschema.Draft202012Validator.check_schema(tool.outputSchema)
                    status = structured(await session.call_tool('get_chain_status', {}))
                    assert status['nodeMode'] == 'full' and status['finalizedBlock'] is None
                    if expected is None:
                        assert status['chain'] is None and status['bestBlock'] is None
                        unavailable = structured(await session.call_tool('get_parameters', {}), failed=True)
                        assert unavailable['error']['code'] == '0'
                    else:
                        # Frozen independent fixture values, not another query through the implementation under test.
                        block_hash = expected['header_hash']
                        assert status['bestBlock'] == dict(header_hash=block_hash, slot=str(expected['slot']))
                        assert status['chain']['genesisStateRoot'] == expected['state_root']
                        parameters = structured(await session.call_tool('get_parameters', {}))['value']['V1']
                        assert parameters['deposit_per_item'] == '18446744073709551615'
                        assert isinstance(parameters['val_count'], str)
                        root = structured(await session.call_tool('get_block', {'block_hash': block_hash}))
                        assert root['block_hash'] == block_hash and root['value'] == expected['state_root']
                        services = structured(await session.call_tool('list_services', {'block_hash': block_hash}))
                        assert '42' in services['value'] and all(isinstance(value, str) for value in services['value'])
                        arguments = dict(block_hash=block_hash, service_id=42)
                        metadata = structured(await session.call_tool('get_service', arguments))
                        assert metadata['value'] == expected['metadata']
                        stored = structured(await session.call_tool('get_storage', dict(arguments, key='a2V5')))
                        assert stored['value'] == expected['value']
                        assert base64.b64decode(stored['value'], validate=True) == b'hello\0world'
                        preimage = structured(await session.call_tool('get_preimage', dict(
                            arguments, preimage_hash=expected['preimage_hash'])))
                        assert preimage['value'] == expected['preimage']
                        empty = structured(await session.call_tool('get_storage', dict(arguments, key='')))
                        assert empty['value'] == ''
                        absent = structured(await session.call_tool('get_service', dict(arguments, service_id=41)))
                        assert absent['value'] is None
                        unknown = structured(await session.call_tool('get_block', dict(
                            block_hash=base64.b64encode(bytes(32)).decode())), failed=True)
                        assert unknown['error']['code'] == '1'
                    try:
                        # Protocol-level invalid arguments must survive SDK decoding as a real McpError.
                        await session.call_tool('get_block', {})
                    except McpError as error:
                        assert error.error.code == -32602
                    else:
                        raise AssertionError('SDK accepted missing required tool arguments')
                    try:
                        await session.call_tool('not_a_tool', {})
                    except McpError as error:
                        assert error.error.code == -32602
                    else:
                        raise AssertionError('SDK accepted an unknown tool')
                    # A failed tool/request must leave the same SDK session usable for concurrent real messages.
                    await asyncio.gather(session.send_ping(), session.list_tools())
    return verify_trace(recorder.events)


def run_case(binary, certificates, folder, name):
    """Each scenario owns a fresh peer and two independently initialized SDK clients."""
    sys.path.insert(0, str(ROOT/'tests'))
    from mcp_checks import free_port
    from rpc_checks import ready
    import socket

    folder.mkdir(parents=True, exist_ok=True)
    stop = folder/'stop'
    stop.unlink(missing_ok=True)
    port = free_port()
    log = folder/'peer.log'
    command = [str(binary), 'server', '--net-port', str(free_port(socket.SOCK_DGRAM)),
               '--net-cert', str(certificates/'a.cert.pem'), '--net-key', str(certificates/'a.key.pem'),
               '--net-peer-key', '-', '--net-alpn', 'jamnp-s/1/00000000', '--net-timeout-ms', '30000',
               '--net-mode', 'service', '--with-mcp', '--mcp-port', str(port)]
    expected = None
    if name != 'unconfigured':
        command += ['--chain', str(ROOT/'tests/fixtures/rpc-services.json')]
        expected = json.loads((ROOT/'tests/fixtures/rpc-services-result.json').read_text())
    if name == 'canonical':
        command.append('--with-state')
    with log.open('wb') as output:
        child = subprocess.Popen(command, cwd=folder, env={**os.environ, 'RAGNAROK_SERVICE_STOP': str(stop)},
                                 stdout=output, stderr=subprocess.STDOUT)
        try:
            ready(child, log)
            # Reinitializing fresh clients also verifies no socket/ID/schema state leaks between connections.
            sessions = [asyncio.run(sdk_session(port, folder, index, expected)) for index in range(2)]
            stop.touch()
            assert child.wait(timeout=5) == 2, log.read_text() # Empty QUIC workloads deliberately return 2.
            assert 'SERVICE_DONE 0 0 0' in log.read_text()
            return dict(passed=True, sessions=sessions)
        finally:
            if child.poll() is None:
                child.kill()
            child.wait(timeout=5)


def main():
    """Persist provenance and bounded diagnostics on success, SDK absence, startup failure or protocol mismatch."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--peer', type=Path, default=ROOT/'build/ragnarok')
    parser.add_argument('--output', type=Path, default=ROOT/'build/tests/mcp-interop')
    args = parser.parse_args()
    folder = args.output.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    report = dict(passed=False, protocol=PROTOCOL, sdk=dict(name='mcp', expected=SDK_VERSION),
                  environment=dict(python=platform.python_version(), system=platform.system(),
                                   machine=platform.machine()), scenarios={})
    try:
        report['sdk']['observed'] = version('mcp')
        assert report['sdk']['observed'] == SDK_VERSION, 'Run make mcp-interop-python for the pinned SDK'
        binary = args.peer.resolve()
        report['binary_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
        report['requirements_sha256'] = hashlib.sha256((ROOT/'tools/mcp-interop-requirements.txt').read_bytes()).hexdigest()
        report['driver_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        report['fixtures_sha256'] = {name: hashlib.sha256((ROOT/'tests/fixtures'/name).read_bytes()).hexdigest()
                                    for name in ('rpc-services.json', 'rpc-services-result.json')}
        sys.path.insert(0, str(ROOT/'tests'))
        from test_quic import fixtures
        certificates = fixtures(folder/'certificates')
        for name in CASES:
            report['scenarios'][name] = dict(passed=False)
            report['scenarios'][name] = run_case(binary, certificates, folder/name, name)
            assert report['scenarios'][name]['passed'] is True, 'Incomplete SDK scenario: ' + name
        report['passed'] = True
    except Exception as error:
        # SDK errors may be nested task-group exceptions; retain the full chain only in ignored evidence.
        report['failure'] = repr(error)
        report['traceback'] = traceback.format_exc()
    finally:
        (folder/'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print(('PASS' if report['passed'] else 'FAIL') + ' official MCP SDK interoperability')
    print('Evidence: ' + str(folder/'results.json'))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
