## Retained raw values remain private immutable storage.
import ../../../src/state_service_values
let owner = default(ServiceValueSnapshot)
discard owner.data
