# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independently authored complete observations preserve expected transition bytes and explicit provenance."""
import unittest
import current_stf_trace_observations_oracle as reference


class TraceObservationsOracle(unittest.TestCase):
    """Successful and refused observations never authorize replacing the original golden trace."""

    def test_frozen_whole_maps(self):
        """Forty chains cover255 transitions and seven precise observed/golden failures."""
        jobs, answers, evidence = reference.expected_observations()
        self.assertEqual((len(jobs),evidence['transitions'],evidence['rejected_jobs']),(47,255,7))
        self.assertIn('no external engine execution',evidence['traces']['observation_origin'])
        for job in jobs[:40]:
            self.assertEqual(job['observations'],[reference.post_state(step) for step in job['steps']])
        self.assertEqual(answers[-4:],
            ['C ImportFailure 0 ObservationMismatch','C ImportFailure 1 ObservationMismatch',
             'C ImportFailure 0 PostStateMismatch','C ImportFailure 1 CandidateFailure'])
        self.assertIsNone(jobs[40]['observations'][0])
