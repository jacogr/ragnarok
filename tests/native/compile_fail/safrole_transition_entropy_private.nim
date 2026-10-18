## Coordinator results expose neither partial state nor mutable stage reasons.
import ../../../src/state/safrole_transition
var hidden = default(SafroleTransitionResult)
discard hidden.entropyReason
