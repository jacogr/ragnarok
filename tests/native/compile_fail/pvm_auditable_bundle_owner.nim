# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged bundle authority through private byte/result storage.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/auditable_bundle
var candidate: AuditableBundle
discard candidate.data
