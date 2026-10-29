# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored sibling headers vary only the eligible uniform-roster author and the genuine corresponding seal.
import std/assertions
import ./[current_consecutive_context, accumulation_current_chain_context]
import ../../src/chain/genesis
import ../../src/codec/[bounded, header, block_codec]
import ../../src/codec/state/[safrole as state_safrole, layout as state_layout]
import ../../src/state/store
import ../../src/bandersnatch/bandersnatch
proc fuzzSiblingChild*(parent: BlockSnapshot, author: AuthorIndex): OwnedBlock =
  ## The maintained same-epoch scalar-one fixture has six eligible identical keys; author statistics still differ.
  assert uint16(author) < 6, "sibling author"
  let original = currentEmptyChild(parent)
  var wire = newSeq[byte](original.blockInfo.value.consumed)
  assert original.encodeOwnedBlock(wire).error == FrameError.None, "sibling input copy"
  assert wire.len == 304, "sibling empty-body extent"
  wire[102] = byte(uint16(author))
  wire[103] = 0
  let entropy = decodeStateEntropy(parent.stateSnapshot.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value
  var scalar = default(array[32, byte])
  scalar[0] = 1
  let key = importScalar(scalar).value
  var context: seq[byte] = @[]
  for c in "jam_fallback_seal": context.add(byte(c)) # Exact GP domain precedes the fixed entropy word.
  for octet in array[32, byte](entropy[3]): context.add(octet)
  let sealed = sign(key, context, wire.toOpenArray(0, 200)).value
  for index, octet in array[96, byte](sealed): wire[
      201+index] = octet # The complete unsigned header is rebound to this author's signature.
  let decoded = decodeBlock(wire, currentConsecutiveLimits().reporting.admission.frame)
  assert decoded.error == FrameError.None, "sibling decode: " & $decoded.error
  assert decoded.value.consumed == wire.len, "sibling consumption"
  decoded.value.owner
