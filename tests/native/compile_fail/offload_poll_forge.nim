## Caller code cannot forge pending results or duplicate a live worker-pool owner.
import ../../../src/quic/offload
discard OffloadPollResult(hasCompletion: true)
