## External safe code cannot read or retag private transition storage.
import ../../../src/state/block_transition
var outcome = default(BlockTransitionResult)
discard outcome.disputesReason # Must fail privacy checking before generating native code.
