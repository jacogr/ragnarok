## Caller code cannot expose or forge unchecked framing metadata.
import ../../../src/quic/protocol
discard FrameResult(status: FrameError.None)
