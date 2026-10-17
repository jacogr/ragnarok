## Callers cannot mutate retained storage or forge guarded service-value success.
import ../../../src/codec/state_service_values
discard ServiceValueResult[int](status: ServiceValueError.None, completed: 0)
