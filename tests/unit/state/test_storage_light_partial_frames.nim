# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded enumeration independently checks whether incomplete local frame fields can have a completion.
import std/[assertions, syncio]
import ../../../src/storage/light/journal/[replay as light_journal_replay,
    manifest as light_journal_manifest]
import ../../../src/storage/light/[delta as light_delta, snapshot as light_snapshot,
    state_cache as light_state_cache]
import ../../../src/storage/[state_proof, database_identity]
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/crypto/primitives
proc put(input: var seq[byte], offset: int, value: uint64) =
  ## Fixture integers use the format's exact eight little-endian bytes.
  for index in 0..<8: input[offset+index] = byte((value shr (8*index)) and 255)
proc matches(input: seq[byte], cut, offset: int, value: int, width: int = 8): bool =
  ## Compare available bytes directly against a small enumerated candidate, without parser arithmetic.
  for index in 0..<width:
    if offset+index < cut and input[offset+index] != byte((uint64(value) shr (8*index)) and 255):
      return false
  true
proc oracle(input: seq[byte], cut, maximum: int): bool =
  ## Exhaust all policy-permitted edit counts and total node/raw combinations, rather than deriving interval formulas.
  for count in 0..2:
    for nodes in 0..count*2:
      for raw in 0..count*3:
        let body = count*42+nodes*64+raw
        if body+208 <= maximum and matches(input, cut, 160, count) and matches(input, cut, 168, body):
          return true
  false
proc plan(input: seq[byte], cut: int, anchor: seq[byte], image: PreparedLightSnapshot,
    manifest: LightJournalManifest, maximum: int): bool =
  ## Planning may retain only the original authenticated checkpoint when all available fields are still possible.
  var journal = anchor
  for index in 0..<cut: journal.add(input[index])
  let outcome = planLightJournalTail(journal, manifest, image, LightReplayLimits(
    bytes: ByteLimit(4096), frames: ElementLimit(1), frame: LightDeltaLimits(
      items: ElementLimit(2), bytes: ByteLimit(maximum))))
  if outcome.error == LightReplayError.None:
    assert outcome.value.prefix.frameCount == 0, "incomplete edits gained replay authority"
    assert outcome.value.prefix.byteLength == anchor.len, "incomplete edits changed retained extent"
    return true
  false
proc main() =
  ## A genuine empty-root frame supplies fixed identity bytes; enumeration edits only local count/body fields.
  let policy = LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(
    items: ElementLimit(2), writes: ElementLimit(2), valueBytes: ByteLimit(6),
    proof: StateProofLimits(nodes: ElementLimit(2), valueBytes: ByteLimit(3))))
  let image = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [], policy).value
  let manifest = prepareLightJournalManifest(image, ManagedEpoch(1), LightDeltaSequence(0),
      ByteLimit(171)).value
  let anchor = encodeLightJournalAnchor(manifest, ByteLimit(98)).value
  let empty = prepareLightDelta(image, LightDeltaSequence(1), [], [], LightDeltaLimits(
    items: ElementLimit(2), bytes: ByteLimit(1024))).value
  var input = newSeq[byte](218)
  for index in 0..<176: input[index] = empty.bytes[index]
  for maximum in [258, 420]:
    # Partial count and body fields must agree with at least one independently enumerated completion.
    for count in 0..4:
      put(input, 160, uint64(count))
      for body in 0..maximum-206:
        put(input, 168, uint64(body))
        for cut in 160..176:
          let expected = oracle(input, cut, maximum)
          let actual = plan(input, cut, anchor, image, manifest, maximum)
          if actual != expected:
            echo "header mismatch ", maximum, " ", count, " ", body, " ", cut
          assert actual == expected, "partial header completion disagreed with enumeration"
  for count in 1..2:
    # The first admit's known metadata must leave an exactly representable payload for the remaining edit.
    put(input, 160, uint64(count))
    input[207] = 1
    for body in count*42..212:
      put(input, 168, uint64(body))
      for nodes in 0..4:
        input[208] = byte(nodes)
        input[209] = 0
        for raw in 0..6:
          put(input, 210, uint64(raw))
          for cut in 208..218:
            var expected = false
            for firstNodes in 0..2:
              for firstRaw in 0..3:
                for nextNodes in 0..(count-1)*2:
                  for nextRaw in 0..(count-1)*3:
                    let size = count*42+(firstNodes+nextNodes)*64+firstRaw+nextRaw
                    if size == body and matches(input, cut, 208, firstNodes, 2) and matches(input,
                        cut, 210, firstRaw):
                      expected = true
            let actual = plan(input, cut, anchor, image, manifest, 420)
            if actual != expected:
              echo "payload mismatch ", count, " ", body, " ", nodes, " ", raw, " ", cut
            assert actual == expected, "partial payload completion disagreed with enumeration"
  for count in 1..2:
    for nodes in 0..2:
      for raw in 0..3:
        # Structurally complete fixtures cover every proper prefix, including payload and checksum bytes.
        let body = count*(42+64*nodes+raw)
        var complete = newSeq[byte](208+body)
        for index in 0..<176: complete[index] = empty.bytes[index]
        put(complete, 160, uint64(count))
        put(complete, 168, uint64(body))
        var cursor = 176
        for edit in 0..<count:
          complete[cursor+30] = byte(edit)
          complete[cursor+31] = 1
          complete[cursor+32] = byte(nodes)
          put(complete, cursor+34, uint64(raw))
          cursor += 42+64*nodes+raw
        let checksum = array[32, byte](blake2b256(complete.toOpenArray(0, cursor-1)).value)
        for index in 0..<32: complete[cursor+index] = checksum[index]
        for cut in 1..<complete.len:
          assert plan(complete, cut, anchor, image, manifest, 1024), "possible proper prefix refused"
  put(input, 160, 2)
  put(input, 168, 84)
  for index in 176..<207: input[index] = 255
  # The largest possible first key cannot leave a canonical successor, even before its tag arrives.
  assert not plan(input, 207, anchor, image, manifest, 420), "exhausted key space admitted"
  echo "light partial frame enumeration passed"
main()
