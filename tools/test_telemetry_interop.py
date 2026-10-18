#!/usr/bin/env python3
"""Opt-in real JAM Tart collector check; launch only caller-selected binaries on loopback."""
import argparse
from contextlib import ExitStack
import hashlib
import json
from pathlib import Path
import socket
import subprocess
import sys
import time
from urllib.error import URLError
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/tests/telemetry-interop'
# Public decoder variant names for the implemented JIP-3 v1 subset.
VARIANTS = {10: 'Status', 21: 'ConnectingIn', 22: 'ConnectInFailed', 23: 'ConnectedIn',
            24: 'ConnectingOut', 25: 'ConnectOutFailed', 26: 'ConnectedOut', 27: 'Disconnected'}
# Each case has a private collector and requires a complete, exact lifecycle for its exporters.
LIFECYCLES = {'exchange': {'server': [21, 23, 27], 'client': [24, 26, 27]},
              'incoming-rejection': {'server': [21, 22]},
              'outgoing-timeout': {'client': [24, 25]}}


# Hold reservations together so the two collector endpoints cannot accidentally select the same port.
def ports():
    with ExitStack() as reservations:
        selected = []
        for kind in (socket.SOCK_STREAM, socket.SOCK_STREAM, socket.SOCK_DGRAM):
            # Readiness still exposes a competing process binding after these reservations are released.
            reservation = reservations.enter_context(socket.socket(socket.AF_INET, kind))
            reservation.bind(('127.0.0.1', 0))
            selected.append(reservation.getsockname()[1])
        return selected


# Retire only a child owned by this harness, even when collector validation fails.
def stop(child):
    if child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill() # Bounded cleanup after an unresponsive child; never the success verdict.
            child.wait(timeout=5)


# Decode only bounded JSON envelopes; handshake/control messages count toward the global capture bound.
def receive(stream, messages, deadline):
    assert len(messages) < 128, 'unbounded collector response count'
    remaining = deadline - time.monotonic()
    assert remaining > 0, 'collector observation deadline'
    stream.settimeout(min(8, remaining))
    raw = stream.recv()
    assert isinstance(raw, str) and len(raw) <= 256 * 1024, 'invalid collector JSON extent'
    value = json.loads(raw)
    assert isinstance(value, dict), value
    messages.append(value)
    assert value.get('type') != 'error', value
    return value


# JAM Tart may coalesce adjacent events into one public batch envelope; never discard those events.
def event_rows(message):
    if message['type'] == 'event':
        return [message['data']]
    if message['type'] == 'batch':
        batch = message['data']
        assert isinstance(batch, list) and 0 < len(batch) <= 64, 'invalid collector batch'
        assert all(row.get('type') == 'event' for row in batch), batch
        return [row['data'] for row in batch]
    return [] # Subscription and periodic statistics are control messages, not JIP-3 events.


# Verify typed collector output independently of Ragnarok's wire encoder and Python capture decoder.
def verify(events, identities, server_port, scenario='exchange'):
    expected = LIFECYCLES[scenario]
    rows = {identities[role]: [] for role in expected}
    for event in events:
        # Only this case's explicitly enabled exporters may contribute to its private collector.
        assert event['node_id'] in rows, event
        rows[event['node_id']].append(event)
    for role, expected_tags in expected.items():
        identity = identities[role]
        # WebSocket envelope IDs are collector-global; JIP-3 references use the per-node event position.
        stream = rows[identity]
        assert 0 < len(stream) < 64, (role, stream)
        lifecycle, attempt = [], None
        remote = identities['client' if role == 'server' else 'server']
        for position, row in enumerate(stream):
            tag = row['event_type']
            assert tag in VARIANTS, row # Unimplemented events and lost observations invalidate every case.
            assert list(row['event']) == [VARIANTS[tag]], row
            fields = row['event'][VARIANTS[tag]]
            assert isinstance(fields['timestamp'], int) and fields['timestamp'] > 0, row
            if tag == 10:
                # Core count comes from decoded registration; unimplemented facilities remain genuinely empty.
                assert fields['num_peers'] in ((0, 1) if scenario == 'exchange' else (0,)), fields
                assert fields['num_guarantees'] == [0, 0], fields
                for key in ('num_val_peers', 'num_sync_peers', 'num_shards', 'shards_size',
                            'num_preimages', 'preimages_size'):
                    assert fields[key] == 0, (key, fields)
                continue
            lifecycle.append(tag)
            if tag in (21, 24):
                attempt = position
                address = fields['from'] if tag == 21 else fields['to']['peer_address']
                assert address['ipv6'] == list(bytes.fromhex('00000000000000000000ffff7f000001'))
                assert 0 < address['port'] <= 65535
                if tag == 24:
                    assert address['port'] == server_port
                    assert bytes(fields['to']['peer_id']).hex() == remote
            elif tag in (22, 23, 25, 26):
                assert attempt is not None and fields['connecting_id'] == attempt, row
                if tag in (22, 25):
                    # Native failure does not expose a reliable diagnosis; the decoded reason stays empty.
                    assert fields['reason'] == '', fields
                if tag == 23:
                    assert bytes(fields['peer_id']).hex() == remote
            else:
                # Only observed authenticated closure may carry this identity, with unknown cause left absent.
                assert bytes(fields['peer']).hex() == remote
                assert fields['terminator'] is None and fields['reason'] == '', fields
        assert lifecycle == expected_tags, (role, lifecycle)
    if 'server' in expected:
        # The server's decoded status is also the readiness barrier before starting its client.
        assert any(row['event_type'] == 10 for row in rows[identities['server']]), 'missing periodic status'
    return {role: len(rows[identities[role]]) for role in expected}


# Exercise an unmodified collector through public TCP ingestion and WebSocket output, without a database.
def run(binary, collector, report, scenario, folder):
    import websocket # Installed only by the explicit opt-in Make target.
    sys.path.insert(0, str(ROOT/'tests'))
    from test_quic import fixtures
    folder.mkdir(parents=True, exist_ok=True)
    certificates = folder/'certificates'
    fixtures(certificates)
    identities = {role: (certificates/f'{key}.pub').read_bytes().hex()
                  for role, key in (('server', 'a'), ('client', 'b'))}
    telemetry_port, api_port, udp_port = ports()
    endpoint = f'127.0.0.1:{telemetry_port}'
    messages = report['messages'] = []
    with ExitStack() as owners:
        # File-backed diagnostics survive every startup, framing and authentication failure.
        def launch(name, arguments):
            output = owners.enter_context((folder/f'{name}.log').open('wb'))
            child = subprocess.Popen([str(arg) for arg in arguments], stdout=output, stderr=subprocess.STDOUT)
            owners.callback(stop, child)
            return child
        backend = launch('collector', [collector, '--no-database', '--telemetry-bind', endpoint,
                         '--api-bind', f'127.0.0.1:{api_port}', '--ingestion-threads', '0'])
        deadline = time.monotonic() + 15
        while True:
            # Readiness is an actual HTTP response from this live child, not a fixed startup sleep.
            assert backend.poll() is None, 'collector exited; see collector.log'
            try:
                with urlopen(f'http://127.0.0.1:{api_port}/api/health', timeout=1) as response:
                    assert response.status == 200
                break
            except (URLError, TimeoutError):
                assert time.monotonic() < deadline, 'collector readiness deadline'
                time.sleep(0.05)
        stream = websocket.create_connection(f'ws://127.0.0.1:{api_port}/api/ws', timeout=8,
                                             http_no_proxy=['127.0.0.1'])
        owners.callback(stream.close)
        deadline = time.monotonic() + 30
        stream.send(json.dumps({'type': 'Subscribe', 'filter': {'type': 'All'}}))
        while receive(stream, messages, deadline)['type'] != 'subscribed':
            pass # Wait for the subscription barrier before producing any telemetry events.
        controls = ['--chain', ROOT/'tests/fixtures/telemetry-dev.json', '--telemetry', endpoint]
        events, children = [], {}
        if scenario != 'outgoing-timeout':
            # Reject b's certificate by pinning a instead; success retains the original eight-request case.
            pin = 'a.pub' if scenario == 'incoming-rejection' else 'b.pub'
            children['server'] = launch('server', [binary, 'server', udp_port, certificates/'a.cert.pem',
                certificates/'a.key.pem', certificates/pin, 'jamnp-s/1/245becfe', '15000', *controls])
            while True:
                # A decoded status proves registration acceptance and an active listener before the dial.
                value = receive(stream, messages, deadline)
                events.extend(event_rows(value))
                assert len(events) < 64, 'unbounded collector event count'
                if any(row['node_id'] == identities['server'] and row['event_type'] == 10 for row in events):
                    break
        else:
            # Hold the UDP endpoint throughout the timeout: no ICMP rejection or competing listener.
            silent = owners.enter_context(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
            silent.bind(('127.0.0.1', 0))
            udp_port = silent.getsockname()[1]
        # The rejecting server is the sole exporter in that case, avoiding assumptions about its remote's TLS state.
        client_controls = [] if scenario == 'incoming-rejection' else controls
        children['client'] = launch('client', [binary, 'client', udp_port, certificates/'b.cert.pem',
            certificates/'b.key.pem', certificates/'a.pub', 'jamnp-s/1/245becfe',
            '6000' if scenario == 'exchange' else '3000', 'clean', *client_controls])
        terminal = {'exchange': 27, 'incoming-rejection': 22, 'outgoing-timeout': 25}[scenario]
        required = 2 if scenario == 'exchange' else 1
        while sum(row['event_type'] == terminal for row in events) < required:
            # Require the expected native outcome, with bounded capture even if an incorrect outcome arrives.
            value = receive(stream, messages, deadline)
            events.extend(event_rows(value))
            assert len(events) < 64, 'unbounded collector event count'
        # The rejecting listener remains alive until its configured lifetime expires after settling TLS.
        report['exit_codes'] = {role: child.wait(timeout=max(0.1, deadline - time.monotonic()))
                                for role, child in children.items()}
        for role, code in report['exit_codes'].items():
            # Negative cases must fail the actual peer operation as well as emit the correct telemetry outcome.
            assert (code == 0) if scenario == 'exchange' else (code > 0), (role, code)
        # Read the collector's retained history after both exporters have closed, including any extra events.
        stream.send(json.dumps({'type': 'GetRecentEvents', 'limit': 64}))
        while True:
            value = receive(stream, messages, deadline)
            if value['type'] == 'recent_events':
                events = value['data']['events']
                assert value['data']['count'] == len(events) < 64
                break
        report['event_counts'] = verify(events, identities, udp_port, scenario)
        report['identities'] = identities
        for role in children:
            # A failed handshake cannot masquerade as a completed application exchange.
            output = (folder/f'{role}.log').read_text()
            if scenario == 'exchange':
                assert 'EXCHANGE_OK 8' in output, role
            else:
                assert 'EXCHANGE_OK' not in output, role
                if role in LIFECYCLES[scenario]:
                    assert 'AUTH_OK' not in output, role
        assert backend.poll() is None, 'collector exited during telemetry ingestion'


# Keep external binary selection explicit and report failure even if setup or decoding raises.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--collector', type=Path, required=True)
    parser.add_argument('--peer', type=Path, default=ROOT/'build/ragnarok')
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    report = dict(passed=False)
    try:
        # Hash actual executables so a result never silently claims a different collector build.
        report['binary_sha256'] = {name: hashlib.sha256(path.read_bytes()).hexdigest()
                                  for name, path in (('collector', args.collector), ('peer', args.peer))}
        report['scenarios'] = {}
        for scenario in LIFECYCLES:
            # Fresh collectors and fixture identities prevent history or node state leaking between cases.
            case = report['scenarios'][scenario] = dict(passed=False)
            run(args.peer.resolve(), args.collector.resolve(), case, scenario, BUILD/scenario)
            case['passed'] = True
        from telemetry_interop_restart import run_restart
        case = report['scenarios']['collector-restart'] = dict(passed=False)
        run_restart(args.peer.resolve(), args.collector.resolve(), case, BUILD/'collector-restart')
        case['passed'] = True
        from telemetry_interop_incoming import run_incoming
        for rejected in (False, True):
            # Each incoming outcome gets fresh collectors, then reuses only its own retained listener.
            name = 'incoming-restart-' + ('rejection' if rejected else 'success')
            case = report['scenarios'][name] = dict(passed=False)
            run_incoming(args.peer.resolve(), args.collector.resolve(), case, BUILD/name, rejected)
            case['passed'] = True
        report['passed'] = True
    except Exception as error:
        report['failure'] = repr(error) # Preserve the diagnostic and fail the optional target honestly.
    finally:
        (BUILD/'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print(('PASS' if report['passed'] else 'FAIL') + ' JAM Tart interoperability')
    print('Evidence: ' + str(BUILD/'results.json'))
    raise SystemExit(0 if report['passed'] else 1)


# Importing pure output validation neither installs dependencies nor launches a collector.
if __name__ == '__main__':
    main()
