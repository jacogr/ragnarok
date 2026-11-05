# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Check bounded pinned-archive recovery with inert responses, no network or upstream execution."""
import hashlib
import http.client
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import call, patch
import urllib.error

import toolchain_archives


class ArchiveDownloads(unittest.TestCase):
    """Exercise retry policy, immutable pins and cache publication through the public download API."""

    def setUp(self):
        """Provide one independent inert pin and capture every network/wait diagnostic boundary."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.archive = self.folder/'tool.archive'
        self.data = b'inert pinned archive bytes; never executable'
        self.pin = dict(url='https://example.invalid/pinned-tool.tar.xz',
                        sha256=hashlib.sha256(self.data).hexdigest())
        self.diagnostics = io.StringIO()
        for name, target, options in (
                ('open', toolchain_archives.urllib.request, dict(attribute='urlopen')),
                ('sleep', toolchain_archives.time, dict(attribute='sleep')),
                ('stderr', toolchain_archives.sys, dict(attribute='stderr', new=self.diagnostics))):
            # Always restore mocks, including when an expected failed download raises.
            patcher = patch.object(target, **options)
            value = patcher.start()
            self.addCleanup(patcher.stop)
            setattr(self, name, value)

    def http_error(self, code):
        """Represent one server refusal without opening a URL or reading a live response."""
        return urllib.error.HTTPError(self.pin['url'], code, 'fixture HTTP failure', {}, None)

    def fetch(self):
        """Use the shared installer entry point with the real checksum and cache implementation."""
        return toolchain_archives.download(self.pin, self.archive)

    def test_transient_http_recovers_with_verified_cache_and_diagnostics(self):
        """Each admitted transient status retries the same pinned URL and caches only complete bytes."""
        for code in (408, 429, 500, 502, 503, 504):
            with self.subTest(code=code):
                self.archive.unlink(missing_ok=True)
                self.open.reset_mock()
                self.sleep.reset_mock()
                response = io.BytesIO(self.data)
                failure = self.http_error(code)
                self.open.side_effect = [failure, response]
                self.sleep.side_effect = lambda delay: self.assertFalse(self.archive.exists())
                self.assertEqual(self.fetch(), self.data)
                self.assertEqual(self.archive.read_bytes(), self.data)
                self.assertEqual(self.open.call_args_list,
                                 [call(self.pin['url'], timeout=60)]*2)
                self.sleep.assert_called_once_with(1)
                self.assertTrue(response.closed)
                self.assertTrue(failure.closed)
        self.assertIn('attempt 1/3', self.diagnostics.getvalue())
        self.assertIn(self.pin['url'], self.diagnostics.getvalue())

    def test_transport_failures_retry_without_retaining_partial_response(self):
        """Timeouts, refused connections and interrupted body reads discard the whole failed attempt."""
        errors = (urllib.error.URLError('temporary name resolution failure'),
                  TimeoutError('fixture timeout'), ConnectionResetError('fixture reset'))
        for error in errors:
            with self.subTest(error=type(error).__name__):
                self.archive.unlink(missing_ok=True)
                self.open.reset_mock()
                self.sleep.reset_mock()
                self.open.side_effect = [error, io.BytesIO(self.data)]
                self.assertEqual(self.fetch(), self.data)
                self.assertEqual(self.open.call_count, 2)
                self.sleep.assert_called_once_with(1)
        self.archive.unlink()
        partial = io.BytesIO(b'unverified partial body')
        with patch.object(partial, 'read', side_effect=http.client.IncompleteRead(b'partial', 20)):
            self.open.side_effect = [partial, io.BytesIO(self.data)]
            self.sleep.side_effect = lambda delay: self.assertFalse(self.archive.exists())
            self.assertEqual(self.fetch(), self.data)
        self.assertTrue(partial.closed)
        self.assertEqual(self.archive.read_bytes(), self.data)

    def test_exhaustion_raises_original_error_and_leaves_no_cache(self):
        """Repeated gateway failures stop after three requests and two short waits."""
        failures = [self.http_error(504) for _ in range(3)]
        self.open.side_effect = failures
        with self.assertRaises(urllib.error.HTTPError) as caught:
            self.fetch()
        self.assertIs(caught.exception, failures[-1])
        self.assertEqual(self.open.call_count, 3)
        self.assertEqual(self.sleep.call_args_list, [call(1), call(2)])
        self.assertEqual(list(self.folder.iterdir()), [])
        self.assertIn('attempt 3/3', self.diagnostics.getvalue())

    def test_permanent_http_errors_never_retry(self):
        """Missing/forbidden assets and unsupported HTTP services remain immediate source/setup failures."""
        for code in (400, 401, 403, 404, 410, 501, 505):
            with self.subTest(code=code):
                self.open.reset_mock()
                self.sleep.reset_mock()
                error = self.http_error(code)
                self.open.side_effect = error
                with self.assertRaises(urllib.error.HTTPError) as caught:
                    self.fetch()
                self.assertIs(caught.exception, error)
                self.open.assert_called_once_with(self.pin['url'], timeout=60)
                self.sleep.assert_not_called()
                self.assertFalse(self.archive.exists())

    def test_valid_cache_reuses_pinned_bytes_without_network(self):
        """An intact retained archive succeeds without requesting or sleeping."""
        self.archive.write_bytes(self.data)
        self.assertEqual(self.fetch(), self.data)
        self.open.assert_not_called()
        self.sleep.assert_not_called()

    def test_corrupt_cache_fails_without_network_or_replacement(self):
        """Retries do not hide a retained checksum mismatch by silently fetching another archive."""
        self.archive.write_bytes(b'corrupt retained bytes')
        with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
            self.fetch()
        self.assertEqual(self.archive.read_bytes(), b'corrupt retained bytes')
        self.open.assert_not_called()
        self.sleep.assert_not_called()

    def test_fresh_checksum_failure_never_retries_or_populates_cache(self):
        """A successful HTTP response with wrong bytes remains a hard integrity refusal."""
        self.open.return_value = io.BytesIO(b'wrong bytes')
        with self.assertRaises(AssertionError):
            self.fetch()
        self.open.assert_called_once_with(self.pin['url'], timeout=60)
        self.sleep.assert_not_called()
        self.assertEqual(list(self.folder.iterdir()), [])

    def test_checksum_failure_after_transient_does_not_use_remaining_attempt(self):
        """A recovered transport cannot authorize retrying failed pin verification."""
        self.open.side_effect = [self.http_error(504), io.BytesIO(b'wrong recovered bytes')]
        with self.assertRaises(AssertionError):
            self.fetch()
        self.assertEqual(self.open.call_count, 2)
        self.sleep.assert_called_once_with(1)
        self.assertEqual(list(self.folder.iterdir()), [])

    def test_local_cache_publication_failure_is_not_a_network_retry(self):
        """A failed atomic replacement retires its temporary file and preserves the original error."""
        self.open.return_value = io.BytesIO(self.data)
        with patch.object(Path, 'replace', side_effect=PermissionError('fixture publication denied')):
            with self.assertRaisesRegex(PermissionError, 'publication denied'):
                self.fetch()
        self.open.assert_called_once_with(self.pin['url'], timeout=60)
        self.sleep.assert_not_called()
        self.assertEqual(list(self.folder.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
