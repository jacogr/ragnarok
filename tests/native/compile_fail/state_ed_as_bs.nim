## Different public-key schemes retain nominal roles even at the same encoded width.
import ../../../src/codec/state_safrole
var key: StateEdKey
let validator = StateValidator(bandersnatch: key)
discard validator
