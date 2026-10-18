# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Rejected misuse: retained snapshot and result/variant state remain private.
import ../../../src/codec/[owned, composite]
var value = default(OwnedResult[int])
value.error = OwnershipError.None
