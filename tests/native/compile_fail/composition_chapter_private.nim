# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact chapter bytes and their validation profile remain private and immutable.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/codec/state_composition
let part = default(StateChapterSnapshot)
discard part.data
