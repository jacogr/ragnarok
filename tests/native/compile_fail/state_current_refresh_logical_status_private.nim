# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete current planning/source/policy/result authority stays private and guarded.
# @@Verification={"group":"privacy","expected":"status"}
import ../../../src/state/current_logical_refresh
var owner: LogicalRefreshResult
discard owner.status
