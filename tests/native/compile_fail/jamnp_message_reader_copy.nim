# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <MessageReader>", "build_name": "jamnp-message-reader-copy"}

## A parser's mutable buffered input cannot acquire an independent copied owner.
import std/assertions
import "../../../src/jamnp-s/messages"
import ../../../src/codec/bounded

var source = default(MessageReader)
assert source.configure(MessageLimits(messageBytes: ByteLimit(8), streamBytes: ByteLimit(32),
    messages: ElementLimit(2))) == MessageError.None
var duplicate = source
# Both owners are used to require a copy, rather than a last-use move.
discard source.feed([0'u8])
discard duplicate.feed([0'u8])
