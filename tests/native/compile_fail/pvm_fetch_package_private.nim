# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Package capture storage cannot be extracted or mutated through the public context handle.

# @@Verification={"group": "privacy", "expected": "packageData"}

import ../../../src/pvm/host_fetch as pvm_host_fetch
let context = default(FetchContext)
discard context.packageData
