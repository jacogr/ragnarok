## Caller code cannot expose or forge unchecked framing metadata.
import ../../../src/quic/protocol
var result = default(FrameResult)
discard result.payloadSize
