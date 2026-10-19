# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot inject or mutate private retained validator backing storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/codec/state_safrole
let snapshot = ValidatorStateSnapshot(data: nil)
discard snapshot
