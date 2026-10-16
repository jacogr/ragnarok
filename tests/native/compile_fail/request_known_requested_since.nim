## A statically known Requested shape cannot supply an Available timestamp.
import std/assertions
import ../../../src/codec/state_requests
let history = requestedHistory()
assert history.state == RequestState.Requested
discard history.since
