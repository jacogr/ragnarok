## Advertised preimage lengths cannot substitute for absolute history timeslots.
import ../../../src/state_requests
let history = RequestHistory(state: RequestState.Available, since: RequestLength(1))
discard history
