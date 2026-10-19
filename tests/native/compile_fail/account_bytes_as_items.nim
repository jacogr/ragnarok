# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Octet footprint and item footprint have separate domains and widths.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: AccountStorageBytes but wanted: AccountStorageItems"}

import ../../../src/codec/state_accounts
let metadata = ServiceMetadata(storageItems: AccountStorageBytes(1))
discard metadata
