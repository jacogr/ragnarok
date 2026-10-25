# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Partial application head ownership cannot be forged or exposed through mutable backing fields.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/app/light_head
let head = default(LightApplicationHead)
discard head.data
