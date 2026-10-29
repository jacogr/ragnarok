# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot forge success by mutating a policy result discriminator.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/app/download/policy as download_policy
var outcome = default(DownloadPolicyResult)
outcome.status = DownloadPolicyError.None
