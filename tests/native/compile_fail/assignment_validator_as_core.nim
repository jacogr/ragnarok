# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A guarantor validator ordinal cannot silently become a core-sequence position.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "GuarantorIndex"}

import ../../../src/codec/[state_availability, guarantees]
var owner: AvailabilitySnapshot
var index: GuarantorIndex
let value = availabilityAt(owner, index)
discard value
