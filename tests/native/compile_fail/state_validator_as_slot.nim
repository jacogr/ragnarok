## Pending validator ordinals cannot silently become sealer schedule positions.
import ../../../src/codec/[state_consensus, state_safrole]
var owner: SafroleStateSnapshot
var index: StateValidatorIndex
let ticket = sealerTicketAt(owner, index)
discard ticket
