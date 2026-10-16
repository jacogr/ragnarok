## Retained raw values remain private immutable storage.
import ../../../src/codec/state_service_values
let owner = default(ServiceValueSnapshot)
discard owner.data
