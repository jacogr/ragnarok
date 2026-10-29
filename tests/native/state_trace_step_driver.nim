# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compare published TraceStep files against independent exact wires and complete pre/post maps.
import std/[assertions, cmdline, strutils, syncio, parseutils]
import ../../src/state/trace/[step as trace_step, state as trace_state]
import ../../src/state/[store, checkpoint]
import ../../src/codec/block_codec
import ../support/trace_step_context
import ../../src/codec/state/trie as state_trie
import ../../src/codec/bounded
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
  for line in readFile(paramStr(1)).splitLines:
    if line.len == 0: continue # Ignore only the final request-file newline.
    let fields = line.splitWhitespace()
    assert fields.len == 2
    var input = unhex(fields[1])
    var maximum = 0'u64
    assert parseBiggestUInt(fields[0], maximum) == fields[0].len
    var limits = traceStepTestLimits()
    limits.bytes = ByteLimit(maximum)
    let decoded = decodeTraceStep(input, limits)
    if decoded.error != TraceStepError.None:
      case decoded.error
      of TraceStepError.PreStateFailure, TraceStepError.PostStateFailure:
        echo "E ", decoded.error, " ", decoded.stateFailure # Only the selected failed state reason is available.
      of TraceStepError.BlockFailure:
        echo "E ", decoded.error, " ", decoded.blockFailure.error # Preserve existing block framing failure attribution.
      else: echo "E ", decoded.error # Plain failures expose no successful child or field progress.
    else:
      let owner = decoded.value
      for index in 0..<input.len: input[index] = 0 # Every retained field must survive destructive caller-buffer mutation.
      let before = owner.tracePreState.value.traceStateSnapshot.value
      let after = owner.tracePostState.value.traceStateSnapshot.value
      let body = owner.traceBlock.value
      var blockWire = newSeq[byte](body.blockInfo.value.consumed)
      assert body.encodeOwnedBlock(blockWire).error == FrameError.None
      echo "S ", owner.traceStepBytes.value, " ", hex(owner.copyTraceStep(ByteLimit(
          8388608)).value), " ", hex(encodeFullCheckpoint(before, ByteLimit(8388608)).value), " ",
              hex(blockWire), " ",
          hex(encodeFullCheckpoint(after, ByteLimit(8388608)).value)

try:
  main() # I/O failures must fail the complete corpus rather than emit a successful prefix.
except:
  quit(2)
