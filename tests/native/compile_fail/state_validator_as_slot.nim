# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Pending validator ordinals cannot silently become sealer schedule positions.
import ../../../src/codec/[state_consensus, state_safrole]
let owner = default(SafroleStateSnapshot)
let index = default(StateValidatorIndex)
let ticket = sealerTicketAt(owner, index)
discard ticket
