## External safe code cannot read or retag private transition storage.
import ../../../src/state/disputes
var outcome = default(DisputesPlan)
discard outcome.data # Must fail privacy checking before generating native code.
