## Snapshot backing arrays cannot be injected, replaced or exposed by callers.
import ../../../src/codec/state_history
let owner = HistorySnapshot(data: nil)
discard owner
