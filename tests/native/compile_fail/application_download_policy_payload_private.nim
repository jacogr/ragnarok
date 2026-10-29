# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot bypass guarded policy extraction through raw variant fields.
# @@Verification={"group": "privacy", "expected": "policy"}
import ../../../src/app/download/policy as download_policy
let outcome = default(DownloadPolicyResult)
discard outcome.policy
