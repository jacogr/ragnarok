## Callers cannot inject or mutate retained assignment/report backing storage.
import ../../../src/state_availability
let owner = AvailabilitySnapshot(data: nil)
discard owner
