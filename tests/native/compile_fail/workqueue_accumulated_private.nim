## Accumulated hash storage remains private and immutable after capture.
import ../../../src/codec/state_workqueues
let owner = default(AccumulatedSnapshot)
discard owner.data
