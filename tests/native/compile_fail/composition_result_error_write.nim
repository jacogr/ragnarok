## Application code cannot forge or retag successful composition results.
import ../../../src/codec/state_composition
var parsed = default(StateCompositionResult[StateSnapshot])
parsed.error = StateCompositionError.None
