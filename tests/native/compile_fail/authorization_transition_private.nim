## Failed/default transition result payloads are never public fields.
import ../../../src/state/authorization
import ../../../src/codec/state_trie
let hidden = default(AuthorizationTransitionResult[StateEntry])
discard hidden.completed
