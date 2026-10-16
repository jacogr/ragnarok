## Raw key/value entries cannot forge validated immutable chapter captures.
import ../../../src/[state_composition, state_trie]
let part: StateChapterSnapshot = default(StateEntry)
discard part
