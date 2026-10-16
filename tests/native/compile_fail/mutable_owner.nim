# Snapshot storage is private; safe callers cannot mutate its validated bytes.
import ../../../src/codec/owned
var frame: OwnedFrame
frame.data.wire[0] = 7
