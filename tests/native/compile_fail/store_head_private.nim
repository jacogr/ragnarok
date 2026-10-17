## Public storage APIs must not expose mutable owners or unchecked result payloads.
import ../../../src/state/store

let hidden = default(StateStore)
discard hidden.head
