# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A statically known failed variant cannot be constructed with a decoded value.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/[work_digest, composite]
let invalid = DigestResult(error: CompositeError.Truncated, value: WorkDigest())
discard invalid
