# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Absolute timeslots cannot substitute for parent service IDs.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: AccountSlot but wanted: ServiceIndex"}

import ../../../src/codec/state_accounts as codec_state_accounts
let metadata = ServiceMetadata(parent: AccountSlot(1))
discard metadata
