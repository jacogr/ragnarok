# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Successful signing results cannot be manufactured by object construction.
import ../../../src/crypto/[primitives, guarantee]
discard GuaranteeMessageResult(status: CryptoError.None, completed: default(GuaranteeMessage))
