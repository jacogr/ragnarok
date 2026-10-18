## External safe code cannot read or retag private transition storage.
import ../../../src/state/block_transition
var outcome = default(BlockTransitionResult)
discard outcome.admissionReason # Must fail privacy checking before generating native code.
