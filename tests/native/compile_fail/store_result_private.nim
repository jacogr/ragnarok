## Public storage APIs must not expose mutable owners or unchecked result payloads.
import ../../../src/state/store

let hidden = default(StateStoreResult[StateStoreSnapshot])
discard hidden.completed
