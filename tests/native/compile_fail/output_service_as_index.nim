## Service IDs cannot substitute for output-sequence ordinals.
import ../../../src/state_outputs
let owner = default(OutputLogSnapshot)
discard outputLogAt(owner, ServiceIndex(0))
