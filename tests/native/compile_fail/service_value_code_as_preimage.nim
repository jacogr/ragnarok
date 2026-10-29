# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Code identities cannot silently substitute for preimage lookup identities.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "ServicePreimageHash"}

import ../../../src/codec/state/service_values as state_service_values
import ../../../src/codec/work/digest as work_digest
import ../../../src/codec/bounded
discard servicePreimageKey(ServiceIndex(0), default(CodeHash), ByteLimit(32))
