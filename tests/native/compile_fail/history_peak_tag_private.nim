## External callers cannot expose private optional-peak storage.
import ../../../src/codec/state_history
let value = default(HistoryPeak)
discard value.isPresent
