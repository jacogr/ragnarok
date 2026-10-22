# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Refreshed mutable declarations and typed failure payloads require guarded result selection.
# @@Verification={"group":"privacy","expected":"metadataReason"}
import ../../../src/state/current_refresh
var owner: CurrentRefreshResult
discard owner.metadataReason
