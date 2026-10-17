## External callers cannot expose, retag or fabricate component results or retained roster storage.
import ../../../src/codec/[state_safrole, state_trie]
let value = default(StateComponentResult[StateComponentRead[ValidatorStateSnapshot]])
discard value.completed
