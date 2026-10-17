## Callers cannot mutate retained storage or forge guarded service-value success.
import ../../../src/codec/state_service_values
var owner = default(ServiceValueSnapshot)
owner.data = nil
