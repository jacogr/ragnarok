# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"privacy","expected":"history"}

## A retention policy can only escape atomically validated Options through its read-only accessor.
import ../../../src/app/options
let owner = default(Options)
discard owner.history
