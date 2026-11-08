# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check bounded acquisition retries and final failure propagation without network or real waits."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import call, patch
import download_retry


class DownloadRetry(unittest.TestCase):
    """Provisioning retries must preserve argv, caller input, success and the final failure."""

    def test_last_attempt_can_succeed(self):
        """A service recovering after the final backoff still supplies the requested acquisition."""
        arguments = ['git', 'fetch', 'origin', '--stdin']
        failures = [subprocess.CalledProcessError(7, arguments) for _ in range(4)]
        success = subprocess.CompletedProcess(arguments, 0)
        with patch.object(download_retry.subprocess, 'run', side_effect=[*failures, success]) as run, patch.object(
                download_retry.time, 'sleep') as sleep:
            self.assertIs(download_retry.run(arguments, input='pinned object\n', text=True), success)
        self.assertEqual(sleep.call_args_list, [call(5), call(15), call(45), call(90)])
        self.assertEqual(run.call_count, 5)
        for invocation in run.call_args_list:
            # Every retry requests the same pinned object and refuses a failed child exit.
            self.assertEqual(invocation, call(arguments, input='pinned object\n', text=True, check=True))

    def test_exhaustion_preserves_final_error_and_success_never_waits(self):
        """Five failures remain an error; an immediately available service incurs no backoff."""
        error = subprocess.CalledProcessError(23, ['download'])
        with patch.object(download_retry.subprocess, 'run', side_effect=error) as run, patch.object(
                download_retry.time, 'sleep') as sleep:
            with self.assertRaises(subprocess.CalledProcessError) as caught:
                download_retry.run(['download'])
            self.assertIs(caught.exception, error)
            self.assertEqual(run.call_count, 5)
            self.assertEqual(sleep.call_args_list, [call(5), call(15), call(45), call(90)])
        with patch.object(download_retry.subprocess, 'run', return_value='success'), patch.object(
                download_retry.time, 'sleep') as sleep:
            self.assertEqual(download_retry.run(['download']), 'success')
            sleep.assert_not_called()

    def test_artifact_retry_discards_partial_extraction(self):
        """A retried GitHub artifact must never inherit a truncated first extraction."""
        import pvm_performance_latest
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary)
            calls = []
            def fetch(arguments, **options):
                """Emulate a partial transport failure, followed by a complete fresh extraction."""
                calls.append(arguments)
                if len(calls) == 1:
                    (destination/'partial.json').write_text('truncated')
                    raise subprocess.CalledProcessError(1, arguments, stderr='HTTP 504')
                self.assertFalse((destination/'partial.json').exists())
                (destination/'complete.json').write_text('{}')
                return subprocess.CompletedProcess(arguments, 0, stdout='', stderr='')
            with patch.object(download_retry.subprocess, 'run', side_effect=fetch), patch.object(
                    download_retry.time, 'sleep') as sleep:
                pvm_performance_latest._gh(['run', 'download', '123', '--dir', str(destination)])
            self.assertEqual(len(calls), 2)
            self.assertTrue((destination/'complete.json').is_file())
            sleep.assert_called_once_with(5)

    def test_docker_bootstrap_policy_and_final_exit(self):
        """The pre-Python bootstrap gets all five attempts and preserves an exhausted command's status."""
        script = Path(__file__).resolve().parents[1]/'tools/download_retry.sh'
        for recover in (True, False):
            with self.subTest(recover=recover), tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary)
                command = folder/'acquire'
                command.write_text('#!/bin/sh\nn=$(cat count 2>/dev/null || echo 0)\n'
                                   'n=$((n+1))\necho "$n" > count\n'
                                   + ('[ "$n" -eq 5 ] && exit 0\n' if recover else '')+'exit 23\n')
                command.chmod(0o755)
                sleep = folder/'sleep'
                sleep.write_text('#!/bin/sh\necho "$1" >> waits\n')
                sleep.chmod(0o755)
                result = subprocess.run(['sh', str(script), str(command)], cwd=folder,
                                        env={**os.environ, 'PATH': str(folder)+os.pathsep+os.environ['PATH']},
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0 if recover else 23, result.stderr)
                self.assertEqual((folder/'count').read_text().strip(), '5')
                self.assertEqual((folder/'waits').read_text().splitlines(), ['5', '15', '45', '90'])
