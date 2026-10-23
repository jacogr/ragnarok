# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Uncached preservation cannot bypass bounded physical request key derivation.
# @@Verification={"group":"nominal","expected":"CurrentRequestKeys","early":["planCurrentRefresh(","[1] expected: CurrentRequestKeys but got: PreservedCurrentIdentities"]}
import ../../../src/state/[current_refresh_plan, current_identities]
discard planCurrentRefresh(default(PreservedCurrentIdentities), CurrentRefreshLimits())
