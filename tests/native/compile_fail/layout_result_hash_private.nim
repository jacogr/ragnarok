## External callers cannot expose, retag or mutate state-layout result/metadata storage.
import ../../../src/codec/state_layout
let value = default(StateLayoutResult[StateNodeHash])
discard value.completed
