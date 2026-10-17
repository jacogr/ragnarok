## A report identity cannot become an offender key despite their identical byte width.
import ../../../src/codec/state_disputes
let hash = default(DisputeHash)
let key: OffenderKey = hash
discard key
