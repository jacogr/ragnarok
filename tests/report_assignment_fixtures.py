# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Original report STF post-assurance input and expected proposed C(10); no other transition is synthesized."""
from report_policy_fixtures import prepare as policy_prepare

CASES = ('report_curr_rotation-1', 'report_prev_rotation-1', 'multiple_reports-1',
         'with_avail_assignments-1', 'core_engaged-1')


# Keep complete old/new guarantees, registration times and signatures unchanged.
def prepare(folder):
    return policy_prepare(folder, CASES, 'report-assignments', include_history=True, include_assignments=True)
