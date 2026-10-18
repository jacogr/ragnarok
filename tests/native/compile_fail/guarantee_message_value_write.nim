# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The public message accessor does not export mutable result storage.
import ../../../src/crypto/[primitives, guarantee]
var parsed = default(GuaranteeMessageResult)
parsed.value = default(GuaranteeMessage)
