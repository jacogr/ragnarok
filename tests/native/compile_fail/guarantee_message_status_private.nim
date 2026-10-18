# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Only the read-only reason accessor exposes result status.
import ../../../src/crypto/[primitives, guarantee]
let parsed = default(GuaranteeMessageResult)
discard parsed.status
