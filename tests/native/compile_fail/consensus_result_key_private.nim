## External callers cannot fabricate chapter results or expose/retag private parent/schedule storage.
import ../../../src/codec/[state_consensus, state_safrole, state_trie]
let value = default(SafroleStateResult[StateBsKey])
discard value.completed
