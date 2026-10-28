# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A statically known failed variant cannot be constructed with a decoded value.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "value"}

import ../../../src/codec/work_digest as codec_work_digest
import ../../../src/codec/composite as codec_composite
let invalid = DigestResult(error: CompositeError.Truncated, value: WorkDigest())
discard invalid
