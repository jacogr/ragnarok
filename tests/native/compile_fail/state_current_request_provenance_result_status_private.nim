# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/state/request_identity_history as state_request_identity_history
let source = default(RequestIdentityHistoryResult[RequestIdentityHistory])
discard source.status
