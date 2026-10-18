# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot forge or read private availability transition storage.
import ../../../src/state/block_transition
var outcome = default(BlockTransitionResult)
discard outcome.availabilityReason # Must fail before native generation.
