## Safe callers cannot forge or read private availability transition storage.
import ../../../src/state/availability
var outcome = default(AvailabilityTransitionResult[AvailabilityPlan])
discard outcome.contextReason # Must fail before native generation.
