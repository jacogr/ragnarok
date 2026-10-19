# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Snapshot storage is private; safe callers cannot mutate its validated bytes.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/codec/owned
var frame = default(OwnedFrame)
frame.data.wire[0] = 7
