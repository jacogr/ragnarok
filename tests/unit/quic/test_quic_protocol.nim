# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Parser selftests use the real DER extractor and shared production frame boundary checks, without sockets.
import std/[assertions, syncio]
import ../../../src/quic/protocol

# The original request and response prefixes must remain pending until exact FIN.
proc prefixes() =
  var request = newSeq[byte](37)
  request[0] = 143
  request[1] = 32
  let response = @[3'u8, 0, 0, 0, 1, 2, 3]
  # Payload bytes are opaque here; peer fixture/content eligibility remains a separate layer.
  for server in [true, false]:
    let wire = if server: request else: response
    for length in 0..wire.len:
      let prefix = wire.toOpenArray(0, length-1)
      assert inspectFrame(prefix, server, 1024, false).error == FrameError.Pending
      let boundary = inspectFrame(prefix, server, 1024, true)
      if length == wire.len:
        # Only complete framing at FIN exposes payload and frame extents.
        assert boundary.error == FrameError.None and boundary.extent == wire.len
        assert boundary.size == (if server: 32 else: 3)
      else:
        # Every premature FIN rejects rather than exposing a default/partial size.
        assert boundary.error == FrameError.Truncated

# Replay the original deterministic malformed DER/frame byte generator through the shared parsers.
proc malformed() =
  var state = 0x51554943'u64
  for iteration in 0..<10000:
    var input = default(array[128, byte])
    # This xorshift is deterministic test data, never cryptographic randomness.
    for i in 0..<input.len:
      state = state xor (state shl 13)
      state = state xor (state shr 7)
      state = state xor (state shl 17)
      input[i] = byte(state and 255)
    let length = iteration mod 129
    let bytes = input.toOpenArray(0, length-1)
    var data: nil ptr byte = nil
    if length > 0: data = addr input[0] # Empty DER has no first byte to borrow.
    assert not validPeer(data, csize_t(length), [])
    let boundary = inspectFrame(bytes, iteration mod 2 == 0, (if iteration mod 2 ==
        0: 32 else: 1024), iteration mod 3 == 0)
    if boundary.error == FrameError.None:
      # Success always proves exact FIN and a bounded complete frame.
      assert iteration mod 3 == 0 and boundary.extent == length and boundary.size <= 1024

# Signed ceilings and unsigned E4 extremes cannot expose an unchecked host size.
assert checkedLength([0'u8, 0, 0, 0], 0).value == 0
assert checkedLength([255'u8, 255, 255, 255], 1024).error == FrameError.InvalidLength
assert checkedLength([], 1024).error == FrameError.Truncated
assert checkedLength([0'u8, 0, 0, 0], -1).error == FrameError.InvalidPolicy
let emptyFrame = default(FrameResult)
let emptyLength = default(LengthResult)
assert emptyFrame.error == FrameError.Uninitialized
assert emptyLength.error == FrameError.Uninitialized
prefixes()
malformed()
echo "Nimony protocol: exact prefixes and 10000 malformed DER/frame inputs passed"
