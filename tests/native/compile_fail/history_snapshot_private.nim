## Snapshot backing arrays cannot be injected, replaced or exposed by callers.
import ../../../src/state_history
let owner = HistorySnapshot(data: nil)
discard owner
