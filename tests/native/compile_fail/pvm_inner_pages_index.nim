# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject interchange of independent memory page domains.

# @@Verification={"group": "nominal", "expected": "got: PageCount but wanted: PageIndex"}

import ../../../src/pvm/machine
let item: PageIndex = PageCount(16)
discard item
