# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A writable page count cannot implicitly become a page ordinal.

# @@Verification={"group": "nominal", "expected": "got: PageCount but wanted: PageIndex"}

import ../../../src/pvm/machine
## Test-only holder isolates the nominal mismatch from overloaded call diagnostics.
type Endpoint = object
  page: PageIndex
let wrong = Endpoint(page: PageCount(1))
discard wrong
