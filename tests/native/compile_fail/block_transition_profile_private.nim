# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge report-stage identity, success or its retained profile.
import ../../../src/state/block_transition
let value = default(BlockTransition)
discard value.profile # Private storage must be rejected before lowering.
