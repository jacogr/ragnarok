# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot bypass private or read-only block result and cause state.
import ../../../src/codec/block_codec
var value = default(FrameResult[int])
var cause = default(ComponentFailure)
cause.kind = ComponentKind.Tickets
