## A proven absent peak must not expose a hash, even before runtime checking.
import std/assertions
import ../../../src/codec/state_history
let peak = absentHistoryPeak()
assert not peak.present
discard peak.hash
