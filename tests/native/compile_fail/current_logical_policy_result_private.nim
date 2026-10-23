# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge retained logical startup authority.
# @@Verification={"group": "privacy", "expected": "policy"}
import ../../../src/app/[current_download_policy]
var owner = default(CurrentLogicalPolicyResult)
discard owner.policy
