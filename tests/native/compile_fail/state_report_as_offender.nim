## Report identities cannot silently become offender Ed25519 keys despite their identical byte width.
import ../../../src/state_disputes
var hash: DisputeHash
let source = DisputeState(offenders: @[hash])
discard source
