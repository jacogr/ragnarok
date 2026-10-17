## Callers cannot convert a default failure into success by changing a result discriminator.
import ../../../src/state/authorization
import ../../../src/codec/state_trie
var hidden = default(AuthorizationTransitionResult[StateEntry])
hidden.status = AuthorizationTransitionError.None
