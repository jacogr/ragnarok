## A caller cannot manufacture transition success by changing its discriminator.
import ../../../src/state/entropy
var hidden = default(EntropyTransitionResult[EntropyTimeUpdate])
hidden.status = EntropyTransitionError.None
