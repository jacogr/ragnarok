## Safe callers cannot bypass private or read-only block result and cause state.
import ../../../src/codec/block_codec
var value = default(FrameResult[int])
let cause = default(ComponentFailure)
discard cause.assuranceReason
