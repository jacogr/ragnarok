# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The public reason remains read-only.
import ../../../src/crypto/[primitives, guarantee]
var parsed = default(GuaranteeMessageResult)
parsed.error = CryptoError.None
