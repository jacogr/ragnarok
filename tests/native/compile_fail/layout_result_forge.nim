## External callers cannot expose, retag or mutate state-layout result/metadata storage.
import ../../../src/codec/state_layout
discard StateLayoutResult[StateKey](status: StateLayoutError.None)
