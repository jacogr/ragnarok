## Caller code cannot inspect private completion state or payload.
import ../../../src/quic/offload
let polled = default(OffloadPollResult)
discard polled.hasCompletion
