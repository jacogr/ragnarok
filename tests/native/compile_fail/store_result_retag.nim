## Result status is read-only; callers cannot retag a failure/default into successful payload access.
import ../../../src/state/store

var hidden = default(StateStoreResult[StateStore])
hidden.status = StateStoreError.None
