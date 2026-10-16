## External callers cannot expose, retag or fabricate component results or retained roster storage.
import ../../../src/codec/[state_safrole, state_trie]
discard StateComponentResult[int](status: StateComponentError.None)
