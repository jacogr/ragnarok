# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "contentReason"}

## Callers cannot forge completed restored authority or phase alternatives.
import ../../../src/state/account_checkpoint
var value = default(AccountCheckpointResult)
discard value.contentReason
