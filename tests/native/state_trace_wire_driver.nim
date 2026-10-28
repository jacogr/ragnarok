# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compare published RawState prefixes against independent exact bytes and complete checkpoint maps.
import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import std/parseutils
import ../../src/state/trace_state as state_trace_state
import ../../src/state/store as state_store
import ../../src/state/checkpoint as state_checkpoint
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/bounded as codec_bounded
proc unhex(text: string): seq[byte] =
  ## Decode only the maintained request transport; production codecs validate actual framing and roots.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for index in 0..<result.len:
    var octet: byte = 0
    assert parseHex(text.substr(index*2, index*2+1), octet) == 2
    result[index] = octet # Only exact two-digit test transport fields are admitted.
proc hex(bytes: openArray[byte]): string =
  ## Emit exact lowercase bytes without replacing an empty value with an absence marker.
  const digits = "0123456789abcdef"
  result = ""
  for octet in bytes:
    result.add(digits[int(octet shr 4)])
    result.add(digits[int(octet and 15)])
proc main() {.raises.} =
  ## Every request carries its independent prefix budget; no observed successor supplies expected wire bytes.
  let policy = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4096),
      perValue: ByteLimit(2097152), totalValueBytes: ByteLimit(4194304), nodes: TrieNodeLimit(
          100000)),
      writes: ElementLimit(4096), writeValueBytes: ByteLimit(4194304))
  for line in readFile(paramStr(1)).splitLines:
    if line.len == 0: continue # Ignore only the final request-file newline.
    let fields = line.splitWhitespace()
    assert fields.len == 2
    var input = unhex(fields[1])
    var maximum = 0'u64
    assert parseBiggestUInt(fields[0], maximum) == fields[0].len
    let decoded = decodeTraceState(input, policy, ByteLimit(maximum))
    if decoded.error != TraceStateError.None:
      echo "E ", decoded.error # Typed lexical/resource/root failures contain no consumed-prefix metadata.
    else:
      let owner = decoded.value
      for index in 0..<input.len: input[index] = 0 # A later caller mutation cannot change any owned observation.
      let info = owner.traceStateInfo.value
      let snapshot = owner.traceStateSnapshot.value
      echo "S ", info.consumed, " ", hex(owner.copyTraceState(ByteLimit(8388608)).value), " ",
          hex(encodeTraceState(snapshot, ByteLimit(8388608)).value), " ",
          hex(encodeFullCheckpoint(snapshot, ByteLimit(8388608)).value)
try:
  main() # I/O failures must fail the complete corpus rather than emit a successful prefix.
except:
  quit(2)
