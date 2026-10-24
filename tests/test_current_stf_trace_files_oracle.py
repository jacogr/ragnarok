# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent exact trace-file contents and complete current STF maps precede native file materialization."""
import hashlib
import unittest
import current_stf_trace_files_oracle as reference


class TraceFilesOracle(unittest.TestCase):
    """Filenames are orchestration details; expected complete maps and signed file contents remain independent."""

    def test_exact_file_inputs_and_refusals(self):
        """The file-backed matrix preserves every signed trace, successor and typed refusal from the independently authored reference."""
        requests,lines,evidence=reference.expected_observations()
        self.assertEqual((evidence['transitions'],evidence['chains'],evidence['files'],evidence['refusals']),(255,40,255,765))
        self.assertTrue(all(line.endswith(' trace-file') for line in requests if line.startswith('C ')))
        inputs=[bytes.fromhex(line[2:]) for line in requests if line.startswith('T ')]
        self.assertEqual([hashlib.sha256(wire).hexdigest() for wire in inputs],evidence['traces']['file_sha256'])
        self.assertEqual(sum(line.startswith('O ') for line in lines),255)
        self.assertEqual(sum(line.startswith('R ') for line in lines),765)
