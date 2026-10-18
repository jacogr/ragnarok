# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Successful signing results cannot be manufactured by object construction.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/crypto/[primitives, guarantee]
discard GuaranteeMessageResult(status: CryptoError.None, completed: default(GuaranteeMessage))
