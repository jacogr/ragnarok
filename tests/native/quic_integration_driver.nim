# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent raw-wire requests exercise enabled codec/crypto composition without a transport
## engine.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import ./nimony_batch_support
import ../../src/quic/integration as quic_integration
import ../../src/codec/owned as codec_owned

# Fixture text is bounded; dash preserves explicit empty inputs without a fake zero byte.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty input must reach the production decoder/hash as empty.
  assert text.len mod 2 == 0 and text.len <= 2*(WireCap+16)
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len: result[i] = octet(text[2*i..2*i+1]) # Strict complete byte pairs.

# Render complete public bytes so independent expectations can detect changed or shortened serialization.
proc hexText(data: openArray[byte]): string =
  result = ""
  for b in data: result.add(toHex(int(b), 2).toLowerAscii()) # Every serialized byte is observable.

# Hash requests and expected query keys are independent from the production codec's decoded contents.
proc request(parts: seq[string]) =
  var input = unhex(parts[^1])
  if parts[0] == "K":
    # Any raw preimage, including an invalid digest encoding, has a Blake2b-256 lookup key.
    let checked = preimageKey(input)
    assert checked.error == IntegrationError.None
    echo hexText(array[32, byte](checked.value))
  else:
    # Preserve original bytes for source-stability, child-owner and exact serialization checks.
    assert parts[0] == "C"
    var original = newSeq[byte](input.len)
    for i, b in input: original[i] = b
    let rawKey = unhex(parts[1])
    assert rawKey.len == 32
    var key = default(array[32, byte])
    for i in 0..<32: key[i] = rawKey[i] # No production key derivation supplies the independent expectation.
    let checked = captureDigest(input, PreimageKey(key))
    if checked.error == IntegrationError.None:
      # Every retained representation must reproduce the complete original input after source reuse.
      var copied = newSeq[byte](wireLength(checked.value).value)
      assert copyVerifiedWire(checked.value, copied).value == original.len and copied == original
      let child = verifiedOwner(checked.value)
      assert child.error == IntegrationError.None
      assert encodeOwned(child.value, copied).value == original.len and copied == original
      for b in input: assert b == 0xa5 # The test actually exercised destruction of the borrowed receive contents.
      echo "ok ", hexText(copied)
    else:
      # Codec/trailing preflight failures preserve input; later hash failures retain the intentional source overwrite.
      if checked.error in [IntegrationError.Codec, IntegrationError.Trailing]: assert input == original
      echo ($checked.error).toLowerAscii()

# Trusted corpus file errors cannot masquerade as a typed composition verdict.
proc main() {.raises.} =
  let args = commandLineParams()
  assert args.len == 1
  for line in lines(args[0]): request(line.splitWhitespace()) # Exactly one observation per independent request.

# Report infrastructure failure separately from ordinary typed protocol rejection.
try:
  main()
except:
  quit(2)
