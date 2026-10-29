# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Startup diagnostics retain strict missing-record failures unless joined logging accounts for loss."""
import unittest

from startup_checks import assert_log_records

PREFIX = '2026-10-29 06:45:47Z '


def receipt(count):
    """Construct the exact final bounded-logger warning, independently of the predicate."""
    return PREFIX+'[warn][startup] logging dropped='+str(count)+'\n'


class StartupLogRecords(unittest.TestCase):
    """Exercise positive receipts and negative missing, forged, insufficient and split-record cases."""

    def test_complete_records_need_no_receipt(self):
        """All physical records remain required when no producer reports loss."""
        assert_log_records('READY\n'+PREFIX+'[info][startup] UI listening\n'
                           +PREFIX+'[info][startup] Stopping UI\n', ['UI listening', 'Stopping UI'])
        with self.assertRaises(AssertionError):
            assert_log_records(PREFIX+'[info][startup] Stopping UI\n', ['UI listening', 'Stopping UI'])

    def test_reported_master_failure_is_accounted(self):
        """The reported HTTP-success case has one absent UI record and a final three-record loss."""
        text = 'READY\n'+''.join(PREFIX+'[info][startup] '+message+'\n' for message in [
            'RPC listening', 'MCP listening', 'Stopping UI', 'Stopping RPC', 'Stopping MCP'])
        expected = ['UI listening', 'RPC listening', 'MCP listening',
                    'Stopping UI', 'Stopping RPC', 'Stopping MCP']
        assert_log_records(text+receipt(3), expected)
        with self.assertRaises(AssertionError):
            assert_log_records(text, expected)

    def test_missing_records_cannot_exceed_reported_loss(self):
        """A drop summary is a finite allowance, never a blanket pass."""
        assert_log_records(receipt(2), ['UI listening', 'RPC listening'])
        with self.assertRaises(AssertionError):
            assert_log_records(receipt(1), ['UI listening', 'RPC listening'])

    def test_related_status_fields_spend_one_record(self):
        """One lost status record can contain several fields without inventing additional drops."""
        assert_log_records(receipt(1), [('Waiting for peers', 'sync target: unknown')])
        assert_log_records(PREFIX+'[info][startup] Waiting for peers, sync target: unknown\n',
                           [('Waiting for peers', 'sync target: unknown')])
        with self.assertRaises(AssertionError):
            assert_log_records('Waiting for peers\nsync target: unknown\n',
                               [('Waiting for peers', 'sync target: unknown')])

    def test_only_exact_final_logger_receipt_grants_allowance(self):
        """Embedded text, other targets, malformed counts and nonfinal warnings cannot excuse loss."""
        invalid = [
            'logging dropped=1\n',
            PREFIX+'[info][startup] logging dropped=1\n',
            PREFIX+'[warn][network] logging dropped=1\n',
            PREFIX+'[warn][startup] unrelated logging dropped=1\n',
            receipt(-1), receipt(0), receipt(2**64),
            receipt(1)+'later output\n',
            receipt(1)+receipt(1)]
        for text in invalid:
            with self.subTest(text=text), self.assertRaises(AssertionError):
                assert_log_records(text, ['UI listening'])


if __name__ == '__main__':
    unittest.main()
