# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source/key arrays and selected result authority remain private.
# @@Verification={"group":"privacy","expected":"status"}
import ../../../src/state/current/request_keys as current_request_keys
var owner: CurrentRequestKeyResult[CurrentRequestKeys]
discard owner.status
