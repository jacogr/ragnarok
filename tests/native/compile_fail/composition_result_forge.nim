## Application code cannot forge or retag successful composition results.
import ../../../src/codec/state_composition
discard StateCompositionResult[StateSnapshot](status: StateCompositionError.None,
    completed: default(StateSnapshot))
