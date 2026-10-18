## Safe callers cannot forge or read private availability transition storage.
import ../../../src/state/availability
var outcome = default(AvailabilityPlan)
discard outcome.data # Must fail before native generation.
