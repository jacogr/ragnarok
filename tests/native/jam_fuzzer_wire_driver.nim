# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Inspect pinned upstream session messages through the native owned protocol, never through an STF substitute.
import std/[assertions, cmdline, parseutils, strutils, syncio]
import ../support/fuzz_protocol_context
import ../../src/state/fuzz/protocol as fuzz_protocol
import ../../src/state/[store, checkpoint]
import ../../src/codec/[bounded, header, block_codec]
import ../../src/codec/state/trie as state_trie
proc hex(input: openArray[byte]): string =
  ## Output copied bytes in one exact lowercase representation.
  const digits = "0123456789abcdef"
  result = ""
  for octet in input:
    result.add(digits[int(octet shr 4)])
    result.add(digits[int(octet and 15)])
proc version(source: FuzzVersion): string =
  ## Retain all three fixed version octets without inventing semver compatibility.
  hex([source.major, source.minor, source.patch])
proc state(source: FuzzMessage): string =
  ## Emit the entire canonically serialized opaque map for independent key/value comparison, not just a matching root.
  let snapshot = source.fuzzState.value
  let commitment = snapshot.commitment
  let encoded = encodeFullCheckpoint(snapshot, ByteLimit(8388608))
  assert encoded.error == CheckpointError.None
  let response = newFuzzState(snapshot, fuzzProtocolTestLimits())
  assert response.error == FuzzError.None
  assert array[32, byte](response.value.fuzzState.value.commitment.root) == array[32, byte](
      commitment.root)
  $commitment.entries & " " & hex(array[32, byte](commitment.root)) & " " & hex(encoded.value)
proc main() {.raises.} =
  ## Source fixtures are bounded hexadecimal transport only; every protocol assertion lives in Nim.
  let limits = fuzzProtocolTestLimits()
  for line in readFile(paramStr(1)).splitLines:
    if line.len == 0: continue # The request-file terminator is not an extra input.
    assert line.len mod 2 == 0 and line.len <= 16777216
    var input = newSeq[byte](line.len div 2)
    for index in 0..<input.len:
      var octet: byte = 0
      assert parseHex(line.substr(index*2, index*2+1), octet) == 2
      input[index] = octet
    let decoded = decodeFuzzMessage(input, limits)
    if decoded.error != FuzzError.None:
      echo "E ", decoded.error
      continue # A typed structural refusal carries no successful snapshot or prefix.
    let source = decoded.value
    assert source.copyFuzzMessage(limits.bytes).value == input
    let framed = source.encodeFuzzFrame(limits.bytes).value
    assert fuzzFrameLength(framed.toOpenArray(0, 3), limits.bytes).value == input.len
    for index in 0..<input.len: assert framed[index+4] == input[
        index] # Exact framing/copy properties include original State record order.
    let info = source.fuzzInfo.value
    var detail = ""
    case info.kind
    of FuzzKind.PeerInfo:
      let peer = source.fuzzPeer.value
      var name = newSeq[byte](peer.name.len)
      for index in 0..<name.len: name[index] = byte(peer.name[index])
      detail = $peer.protocol & " " & $peer.features & " " & version(peer.jam) & " " & version(
          peer.app) & " " & hex(name)
    of FuzzKind.Initialize:
      detail = $source.fuzzHeader.value.headerInfo.value.consumed & " " & state(source) & " " &
          $source.fuzzAncestors.value.len
    of FuzzKind.State:
      detail = state(source)
    of FuzzKind.ImportBlock:
      detail = $source.fuzzBlock.value.blockInfo.value.consumed
    of FuzzKind.StateRoot:
      detail = hex(array[32, byte](source.fuzzRoot.value))
    of FuzzKind.GetState:
      detail = hex(array[32, byte](source.fuzzRequestedHeader.value))
    of FuzzKind.Error:
      let text = source.fuzzText.value
      var bytes = newSeq[byte](text.len)
      for index in 0..<text.len: bytes[index] = byte(text[index])
      detail = hex(bytes)
    echo "M ", info.kind, " ", info.bytes, " ", detail
try:
  main() # Missing fixtures, I/O errors and any unexpected assertion fail the complete native comparison.
except:
  quit(2)
