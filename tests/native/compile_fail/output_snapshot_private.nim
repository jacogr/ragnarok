## Retained output arrays remain private and immutable after capture.
import ../../../src/codec/state_outputs
let owner = default(OutputLogSnapshot)
discard owner.data
