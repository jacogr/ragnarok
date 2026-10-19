# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional rejection protects the public disputes type/ownership boundary.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: DisputeHash but wanted: OffenderKey"}

import ../../../src/codec/[disputes]

var value: Culprit
value.key = DisputeHash(default(array[32, byte]))
