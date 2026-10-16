## Retained output arrays remain private and immutable after capture.
import ../../../src/state_outputs
let owner = default(OutputLogSnapshot)
discard owner.data
