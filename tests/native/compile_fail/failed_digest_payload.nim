# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import ../../../src/codec/[work_digest, composite]
# A statically known failed variant cannot be constructed with a decoded value.
let invalid = DigestResult(error: CompositeError.Truncated, value: WorkDigest())
discard invalid
