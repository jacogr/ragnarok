## Callers cannot mutate retained storage or forge guarded service-value success.
import ../../../src/codec/state_service_values
var parsed = default(ServiceValueResult[int])
parsed.value = 0
