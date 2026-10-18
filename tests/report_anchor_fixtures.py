# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Unchanged report STF recent-anchor projections; upstream supplies no retained ancestor headers."""
from report_policy_fixtures import prepare as policy_prepare

CASES = ('report_curr_rotation-1', 'report_prev_rotation-1', 'multiple_reports-1',
         'anchor_not_recent-1', 'bad_anchor_slot-1', 'bad_state_root-1', 'bad_beefy_mmr-1')


# Retain original signatures, preceding policy inputs and recent history; never manufacture external ancestors.
def prepare(folder):
    return policy_prepare(folder, CASES, 'report-anchors', include_history=True)
