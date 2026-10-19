# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Setup owners do not expose native pointers or mutable ARC storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "state"}

import ../../../src/bandersnatch/bandersnatch
let setup = default(BsSetup)
discard setup.state
