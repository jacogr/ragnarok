# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Callers cannot forge completed restored authority or phase alternatives.
import ../../../src/state/account/checkpoint as account_checkpoint
var value = default(AccountCheckpointResult)
discard value.status
