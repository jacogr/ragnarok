## Callers cannot inject or mutate retained assignment/report backing storage.
import ../../../src/codec/state_availability
let owner = AvailabilitySnapshot(data: nil)
discard owner
