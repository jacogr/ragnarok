## Caller code cannot forge pending results or duplicate a live worker-pool owner.
import ../../../src/quic/offload
var result = default(OffloadPollResult)
result.ready = true
