# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Rejected misuse: bounded result state is private and its public reason is read-only.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "elementCount"}

import ../../../src/codec/bounded
let value = default(SequenceResult)
discard value.elementCount
