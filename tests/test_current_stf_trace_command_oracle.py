# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent exact operator configuration and signed whole-map file bundles precede native command execution."""
import hashlib
import json
import unittest
import current_stf_trace_command_oracle as reference
from state_layout_oracle import digest


class TraceCommandOracle(unittest.TestCase):
    """Command inputs retain independent roots, complete maps, full parameter bytes and unmodified signed blocks."""

    def test_complete_frozen_operator_bundles(self):
        """Forty successes and six precise refusals compare the actual offline operator boundary."""
        jobs,expected,evidence=reference.expected_observations()
        self.assertEqual((evidence['cases'],evidence['chains'],evidence['transitions'],evidence['rejected_jobs']),(46,40,255,6))
        self.assertEqual(len(jobs),len(expected))
        self.assertEqual(sum(len(job['steps']) for job in jobs[:40]),255)
        for job,proof in zip(jobs,evidence['traces']['jobs']):
            config=json.loads(job['config'])
            self.assertEqual(config['protocol_parameters'],reference.parameters(job['mode']).hex())
            self.assertEqual(hashlib.sha256(job['config'].encode()).hexdigest(),proof['config_sha256'])
            self.assertEqual([hashlib.sha256(step).hexdigest() for step in job['steps']],proof['steps_sha256'])
        for job in jobs[:40]:
            config=json.loads(job['config']);pairs,extent=reference.raw.prefix(job['genesis'][297:])
            self.assertEqual(config['genesis_state'],{key.hex():value.hex() for key,value in pairs})
            self.assertEqual(bytes.fromhex(config['genesis_header']),job['genesis'][:297])
            self.assertEqual(job['steps'][0][reference.raw.prefix(job['steps'][0])[1]:][:32],digest(job['genesis'][:297]))
        self.assertEqual(expected[-1],'C ImportFailure 1 CandidateFailure')
        self.assertEqual(expected[-3],'C TraceFailure 0 TrailingBytes')
