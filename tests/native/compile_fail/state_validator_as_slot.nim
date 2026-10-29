# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Pending validator ordinals cannot silently become sealer schedule positions.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "StateValidatorIndex"}

import ../../../src/codec/state/[consensus as state_consensus, safrole as state_safrole]
let owner = default(SafroleStateSnapshot)
let index = default(StateValidatorIndex)
let ticket = sealerTicketAt(owner, index)
discard ticket
