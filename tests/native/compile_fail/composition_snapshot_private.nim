## Callers cannot obtain or edit private mapping/child storage.
import ../../../src/state_composition
let owner = default(StateSnapshot)
discard owner.data
