## Construct a new valid shape rather than retagging or writing guarded fields.
import ../../../src/codec/state_requests
discard RequestHistory(mode: RequestState.Available, sinceSlot: RequestSlot(1))
