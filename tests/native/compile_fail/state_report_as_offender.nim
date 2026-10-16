## Report identities cannot silently become offender Ed25519 keys despite their identical byte width.
import ../../../src/codec/state_disputes
var hash: DisputeHash
let source = DisputeState(offenders: @[hash])
discard source
