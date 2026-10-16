## Parent snapshot storage cannot be replaced or exposed by application callers.
import ../../../src/state_consensus
let owner = SafroleStateSnapshot(data: nil)
discard owner
