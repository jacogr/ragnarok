## Pending validator ordinals cannot silently become sealer schedule positions.
import ../../../src/codec/[state_consensus, state_safrole]
let owner = default(SafroleStateSnapshot)
let index = default(StateValidatorIndex)
let ticket = sealerTicketAt(owner, index)
discard ticket
