## Ready source-shaped storage remains private and immutable after capture.
import ../../../src/codec/state_workqueues
let owner = default(ReadySnapshot)
discard owner.data
