## A 144-byte validator BLS key cannot silently replace the ring commitment of equal width.
import ../../../src/codec/[state_consensus, state_safrole]
let key = default(StateBlsKey)
let source = SafroleState(root: key)
discard source
