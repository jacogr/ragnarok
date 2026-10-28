# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject interchange of independent memory page domains.

# @@Verification={"group": "nominal", "expected": "got: PageAccess but wanted: PageContent"}

import ../../../src/pvm/machine as pvm_machine
let item: PageContent = PageAccess.ReadOnly
discard item
