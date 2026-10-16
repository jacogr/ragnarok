## Construct a new valid shape rather than retagging or writing guarded fields.
import ../../../src/codec/state_requests
var history = default(RequestHistory)
history.since = RequestSlot(0)
