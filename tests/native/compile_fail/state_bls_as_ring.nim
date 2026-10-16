## A 144-byte validator BLS key cannot silently replace the ring commitment of equal width.
import ../../../src/[state_consensus, state_safrole]
var key: StateBlsKey
let source = SafroleState(root: key)
discard source
