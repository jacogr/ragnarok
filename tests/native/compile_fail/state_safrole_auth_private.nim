# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authentication result state/payload remain private across default, failed and successful
## outcomes.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/safrole_authentication as state_safrole_authentication
var hidden = default(SafroleAuthResult)
discard hidden.completed
