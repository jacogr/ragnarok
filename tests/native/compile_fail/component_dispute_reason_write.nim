## Safe callers cannot bypass private or read-only block result and cause state.
import ../../../src/codec/block_codec
var value = default(FrameResult[int])
var cause = default(ComponentFailure)
cause.disputeError = default(typeof(cause.disputeError))
