## Caller code cannot forge pending results or duplicate a live worker-pool owner.
import ../../../src/quic/offload
var original = default(OffloadPool)
var duplicate = original
discard busyPool(original)
discard busyPool(duplicate)
