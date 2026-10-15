import ../../../src/guarantees
# External callers cannot reach the private mutable record sequence.
var owner: OwnedGuarantees
discard owner.data
