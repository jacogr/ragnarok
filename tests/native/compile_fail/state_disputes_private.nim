## Application code cannot replace or expose the snapshot's retained mutable storage.
import ../../../src/state_disputes
let owner = DisputeStateSnapshot(data: nil)
discard owner
