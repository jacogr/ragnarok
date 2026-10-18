## External safe code cannot read or retag private transition storage.
import ../../../src/state/disputes
var outcome = default(DisputesResult[DisputesPlan])
discard outcome.status # Must fail privacy checking before generating native code.
