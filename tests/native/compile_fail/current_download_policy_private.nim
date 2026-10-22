# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current policy success tags remain private; malformed/default parse results cannot be retagged.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/app/current_download_policy
var parsed = default(CurrentDownloadPolicyResult)
discard parsed.status
