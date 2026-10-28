# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect SDK wire-evidence, failure propagation and cleanup without requiring optional packages.

The real SDK gate owns interoperability; these tests verify that its harness cannot report a false pass.
"""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
sys.path.insert(0, str(ROOT/'tests'))
import test_mcp_interop as interop


def trace():
    """Author a minimal independent lifecycle transcript with one response per identified request."""
    events = []
    methods = ['initialize', 'notifications/initialized', 'ping', 'tools/list', 'tools/call']
    for index, method in enumerate(methods):
        message = dict(jsonrpc='2.0', method=method)
        if method != 'notifications/initialized':
            message['id'] = index
        headers = {} if method == 'initialize' else {'mcp-protocol-version': interop.PROTOCOL}
        events.append(dict(direction='request', method='POST', headers=headers, message=message))
        response = dict(jsonrpc='2.0', id=index, result={}) if 'id' in message else None
        events.append(dict(direction='response', method='POST', headers={},
                           status=200 if response else 202, message=response))
    return events


class McpInteropHarness(unittest.TestCase):
    def test_wire_requires_correlated_complete_lifecycle(self):
        """A missing response, duplicate ID, missing notification or wrong revision fails trace validation."""
        self.assertEqual(interop.verify_trace(trace()), dict(requests=5, replies=4, tool_calls=1))
        for mutation in ['missing_reply', 'duplicate_id', 'missing_initialized', 'wrong_version', 'session']:
            events = trace()
            if mutation == 'missing_reply':
                events.pop()
            elif mutation == 'duplicate_id':
                events[4]['message']['id'] = 0
            elif mutation == 'missing_initialized':
                del events[2:4]
            elif mutation == 'wrong_version':
                events[4]['headers']['mcp-protocol-version'] = 'future'
            else:
                events[0]['headers']['mcp-session-id'] = 'unwanted'
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                interop.verify_trace(events)

    def test_recording_budget_fails_before_appending(self):
        """Runaway SDK traffic cannot silently truncate evidence or grow its log indefinitely."""
        with tempfile.TemporaryDirectory() as directory:
            recorder = interop.WireRecorder(Path(directory)/'wire.jsonl')
            for index in range(256):
                recorder.append(dict(index=index))
            with self.assertRaises(ValueError):
                recorder.append(dict(index=256))
            self.assertEqual(len(recorder.events), 256)
            self.assertEqual(len(recorder.path.read_text().splitlines()), 256)

    def test_error_does_not_leave_peer_running(self):
        """A failed SDK session kills and joins the real-process owner before propagating failure."""
        child = Mock()
        child.poll.return_value = None

        def fail_sdk(coroutine):
            # A synthetic failure consumes the coroutine it intercepts, without running any SDK imports.
            coroutine.close()
            raise RuntimeError('SDK schema mismatch')

        with tempfile.TemporaryDirectory() as directory, patch('subprocess.Popen', return_value=child), \
                patch('rpc_checks.ready'), patch.object(interop.asyncio, 'run', side_effect=fail_sdk):
            with self.assertRaisesRegex(RuntimeError, 'SDK schema mismatch'):
                interop.run_case(Path('/peer'), Path('/certs'), Path(directory), 'unconfigured')
        child.kill.assert_called_once()
        child.wait.assert_called_once_with(timeout=5)

    def main_result(self, sdk=interop.SDK_VERSION, scenario=None):
        """Exercise the real summary writer while replacing only external package/process setup."""
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            peer = folder/'peer'
            peer.write_bytes(b'fixture executable identity')
            output = folder/'results'
            argv = ['test_mcp_interop', '--peer', str(peer), '--output', str(output)]
            with patch.object(sys, 'argv', argv), patch.object(interop, 'version', return_value=sdk), \
                    patch('test_quic.fixtures', return_value=folder/'certs'), \
                    patch.object(interop, 'run_case', return_value=scenario or dict(passed=True)), \
                    redirect_stdout(io.StringIO()):
                code = interop.main()
            return code, json.loads((output/'results.json').read_text())

    def test_success_requires_every_scenario_and_provenance(self):
        """Only a complete run with the expected external SDK earns a successful summary."""
        code, report = self.main_result()
        self.assertEqual(code, 0)
        self.assertTrue(report['passed'])
        self.assertEqual(set(report['scenarios']), set(interop.CASES))
        self.assertEqual(report['sdk']['observed'], interop.SDK_VERSION)
        self.assertEqual(len(report['binary_sha256']), 64)
        self.assertEqual(len(report['requirements_sha256']), 64)
        self.assertEqual(len(report['driver_sha256']), 64)
        self.assertEqual(set(report['fixtures_sha256']), {'rpc-services.json', 'rpc-services-result.json'})

    def test_wrong_sdk_or_failed_case_remains_failed(self):
        """Version mismatch and a returned failed case cannot become a green aggregate."""
        for arguments in [dict(sdk='unapproved'), dict(scenario=dict(passed=False))]:
            with self.subTest(arguments=arguments):
                code, report = self.main_result(**arguments)
                self.assertEqual(code, 1)
                self.assertFalse(report['passed'])
                self.assertIn('failure', report)

    def test_sdk_lock_matches_observed_pin(self):
        """The driver, direct dependency and hash-locked closure name the same SDK release."""
        direct = (ROOT/'tools/mcp-interop-requirements.in').read_text()
        locked = (ROOT/'tools/mcp-interop-requirements.txt').read_text()
        self.assertIn('mcp=='+interop.SDK_VERSION+'\n', direct)
        self.assertIn('mcp=='+interop.SDK_VERSION+' \\\n    --hash=sha256:', locked)
        entries = [line for line in locked.splitlines() if line and not line.startswith(('#', ' '))]
        self.assertTrue(entries)
        self.assertTrue(all('==' in line and line.endswith('\\') for line in entries))


if __name__ == '__main__':
    unittest.main()
