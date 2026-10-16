## External callers cannot expose, retag or mutate state-layout result/metadata storage.
import ../../../src/codec/state_layout
var value = default(StateLayoutResult[StateKey])
value.error = StateLayoutError.None
