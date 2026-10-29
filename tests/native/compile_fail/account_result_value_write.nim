# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Application code cannot forge success or mutate a read-only result accessor.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "value"}

import ../../../src/codec/state/accounts as state_accounts
var parsed = default(ServiceMetadataResult[ServiceMetadataRead])
parsed.value = default(ServiceMetadataRead)
