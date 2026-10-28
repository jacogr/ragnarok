# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Refused preparation cannot expose a candidate chain through raw variant fields.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/state/accumulation_publication as state_accumulation_publication
let result = default(ChainPreparationResult)
discard result.completed
