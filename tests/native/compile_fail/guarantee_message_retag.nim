# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A caller cannot turn a default failure into a signing credential.
import ../../../src/crypto/[primitives, guarantee]
var parsed = default(GuaranteeMessageResult)
parsed.status = CryptoError.None
