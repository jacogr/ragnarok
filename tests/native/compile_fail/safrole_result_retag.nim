## External callers cannot expose, retag or fabricate component results or retained roster storage.
import ../../../src/codec/[state_safrole, state_trie]
var value = default(StateComponentResult[int])
value.status = StateComponentError.None
