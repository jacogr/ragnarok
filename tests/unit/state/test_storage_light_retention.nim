# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## An independent complete-root small-map model checks quota eviction, protected queries and atomic immutable admission.
# @@Verification={"arc":"storage_light_retention_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../support/storage_light_root
import ../../support/storage_light_journal
import ../../../src/storage/light_snapshot as storage_light_snapshot
import ../../../src/storage/light_state_cache as storage_light_state_cache
import ../../../src/storage/state_proof as storage_state_proof
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Clear provider observations independently of source/model construction.
proc refuseAfter(count: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse each actual proof/checksum hash without inventing a completed proof.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## A planner and all pure quota refusals must remain crypto-free.
type
  Model = object ## The independent five-slot model carries only explicit expected proof membership and removals.
    fits: bool
    kept: seq[LightStateProof]
    removed: seq[StateKey]
func sameKeys(left, right: openArray[StateKey]): bool =
  ## Compare all serialized octets explicitly, independently of generic container equality for nominal keys.
  if left.len != right.len: return false
  for index in 0..<left.len:
    let a = array[31, byte](left[index])
    let b = array[31, byte](right[index])
    for octet in 0..<31:
      if a[octet] != b[octet]: return false
  true
proc inputs(fixture: LightRootFixture): array[5, LightStateProof] =
  ## Rebuild the complete source map independently to obtain a previously unknown query's authenticated absence.
  var long = newSeq[byte](33)
  for index in 0..<33: long[index] = 7
  let trie = newFullStateTrie([StateEntry(key: lightKey(0), value: long),
    StateEntry(key: lightKey(32), value: @[11'u8]), StateEntry(key: lightKey(128))],
    FullStateTrieLimits(trie: StateTrieLimits(items: ElementLimit(8), nodes: TrieNodeLimit(10000),
      perValue: ByteLimit(64), totalValueBytes: ByteLimit(128)))).value
  assert array[32, byte](trie.commitment.root) == array[32, byte](fixture.oldConfig.root), "retention witness 29"
  [fixture.sourceProofs[0], fixture.sourceProofs[1],
    LightStateProof(key: lightKey(64), proof: trie.prove(lightKey(64),
        fixture.oldConfig.snapshot.cache.proof).value),
    fixture.sourceProofs[2], fixture.sourceProofs[3]]
proc oracle(evidence: array[5, LightStateProof], mask: int, limits: LightRetentionLimits,
    writes: uint64, overhead: int): Model =
  ## Independently charge five explicit slots, then drop unprotected original slots in ascending identity order.
  var keep = [true, true, false, true, true]
  var protected = default(array[5, bool])
  var incoming = 0
  for index in 0..<5:
    protected[index] = (mask and (1 shl index)) != 0
    if protected[index]:
      keep[index] = true
      inc incoming
  var items = 0
  var values = 0
  var bytes = overhead
  for index in 0..<5:
    if keep[index]:
      inc items
      values += evidence[index].proof.value.len
      bytes += 41+64*evidence[index].proof.nodes.len+evidence[index].proof.value.len
  result = Model(kept: @[], removed: @[])
  for index in 0..<5:
    # Incoming identities never become eviction candidates, even when their protected set alone exceeds a ceiling.
    if uint64(items) <= uint64(limits.items) and uint64(values) <= uint64(limits.valueBytes) and
        uint64(bytes) <= uint64(limits.bytes): break
    if keep[index] and not protected[index]:
      keep[index] = false
      result.removed.add(evidence[index].key)
      dec items
      values -= evidence[index].proof.value.len
      bytes -= 41+64*evidence[index].proof.nodes.len+evidence[index].proof.value.len
  result.fits = uint64(items) <= uint64(limits.items) and uint64(values) <= uint64(
      limits.valueBytes) and
    uint64(bytes) <= uint64(limits.bytes) and uint64(result.removed.len) <= uint64(
        limits.evictions) and
    uint64(incoming+result.removed.len) <= writes and uint64(limits.entries) >= 4
  for index in 0..<5:
    if keep[index]: result.kept.add(evidence[index])
proc modelCases(fixture: LightRootFixture, evidence: array[5, LightStateProof]) =
  ## Every incoming subset crosses independent item/value/image ceilings and compares exact canonical output with fresh preparation.
  let empty = prepareLightSnapshot(fixture.oldConfig.chain, fixture.oldConfig.root, [],
      fixture.oldConfig.snapshot).value
  for mask in 0..<32:
    var incoming: seq[LightStateProof] = @[]
    for index in countdown(4, 0):
      if (mask and (1 shl index)) != 0: incoming.add(evidence[index])
    for items in 0..5:
      for values in [0, 1, 33, 34]:
        for bytes in [empty.byteLength, fixture.source.byteLength-1, 8192]:
          let limits = LightRetentionLimits(items: ElementLimit(items), valueBytes: ByteLimit(
              values),
            bytes: ByteLimit(bytes), entries: ElementLimit(4), evictions: ElementLimit(4))
          let expected = oracle(evidence, mask, limits, 8, empty.byteLength)
          resetHash(0)
          let planned = planLightRetention(fixture.source, incoming, limits)
          assert calls() == 0, "planning performs no proof or checksum work"
          let updated = fixture.source.admitRetained(incoming, limits)
          if expected.fits:
            assert planned.error == LightSnapshotError.None, "successful pure retention plan"
            let chosen = planned.value.forgottenKeys
            assert sameKeys(chosen, expected.removed), "model choices mask=" & $mask & " items=" &
                $items & " values=" & $values & " bytes=" & $bytes
            assert updated.error == LightSnapshotError.None, "retained update success"
            let rebuilt = prepareLightSnapshot(fixture.oldConfig.chain, fixture.oldConfig.root,
              expected.kept, fixture.oldConfig.snapshot).value
            assert updated.value.encodedBytes == rebuilt.encodedBytes, "independent canonical retention model"
          else:
            assert planned.error == LightSnapshotError.LimitExceeded and updated.error ==
                LightSnapshotError.LimitExceeded, "model refusal mask=" & $mask
            assert calls() == 0, "impossible retention refuses before crypto"
proc cycle(fixture: LightRootFixture, evidence: LightStateProof, limits: LightRetentionLimits) =
  ## Success, copied plans and late checksum refusal retire all scratch before the ARC observer samples live memory.
  let planned = planLightRetention(fixture.source, [evidence], limits).value
  let copied = planned
  assert copied.len == 1, "retention witness 105"
  let updated = fixture.source.admitRetained([evidence], limits)
  assert updated.error == LightSnapshotError.None, "retained update success"
  resetHash(0)
  refuseAfter(2)
  let failed = fixture.source.admitRetained([evidence], limits)
  assert failed.error == LightSnapshotError.BackendFailure, "retention witness 111"
  resetHash(0)
proc boundaries(fixture: LightRootFixture, evidence: array[5, LightStateProof]) =
  ## Exact work caps, source/default refusals and proof/backend failures preserve every retained source reader and byte.
  let limits = LightRetentionLimits(items: ElementLimit(4), valueBytes: ByteLimit(128),
    bytes: ByteLimit(8192), entries: ElementLimit(4), evictions: ElementLimit(1))
  let original = fixture.source.bytes
  let reader = fixture.source.cache
  let cursor = fixture.source.proofCursor.value
  let planned = planLightRetention(fixture.source, [evidence[2]], limits).value
  assert planned.initialized and planned.len == 1 and sameKeys(planned.forgottenKeys, [lightKey(
      0)]), "retention witness 121"
  var copy = planned.forgottenKeys
  copy[0] = lightKey(255)
  assert sameKeys(planned.forgottenKeys, [lightKey(0)]), "extracted choices cannot mutate opaque plan"
  resetHash(0)
  for mode in 0..4:
    var changed = limits
    if mode == 0: changed.entries = ElementLimit(3)
    elif mode == 1: changed.evictions = ElementLimit(0)
    elif mode == 2: changed.items = ElementLimit(9)
    elif mode == 3: changed.bytes = ByteLimit(0)
    else: changed.valueBytes = ByteLimit(129)
    assert planLightRetention(fixture.source, [evidence[2]], changed).error ==
        LightSnapshotError.LimitExceeded, "retention witness 133"
  assert planLightRetention(default(PreparedLightSnapshot), [], limits).error ==
      LightSnapshotError.Uninitialized, "retention witness 135"
  let duplicate = planLightRetention(fixture.source, [evidence[2], evidence[2]], limits)
  assert duplicate.error == LightSnapshotError.ProofFailure and duplicate.proofError ==
      LightCacheError.DuplicateKey, "retention witness 138"
  assert calls() == 0, "retention witness 140"
  let success = fixture.source.admitRetained([evidence[2]], limits)
  assert success.error == LightSnapshotError.None, "retention witness 142"
  let count = calls()
  assert count == 3, "only one incoming two-node proof and final image checksum"
  for skip in 0..<int(count):
    refuseAfter(cint(skip))
    assert fixture.source.admitRetained([evidence[2]], limits).error ==
        LightSnapshotError.BackendFailure, "retention witness 147"
    assert calls() == cint(skip+1) and fixture.source.encodedBytes == original, "retention witness 149"
  resetHash(0)
  assert fixture.source.admitRetained([fixture.destinationProofs[0]], limits).error ==
      LightSnapshotError.ProofFailure, "retention witness 151"
  var malformed = evidence[2]
  malformed.proof.nodes = newSeq[EncodedStateNode](250)
  resetHash(0)
  assert fixture.source.admitRetained([malformed], limits).error ==
      LightSnapshotError.LimitExceeded and calls() == 0, "retention witness 156"
  let fitted = fixture.source.admitRetained([], limits).value
  assert fitted.encodedBytes == original and calls() == 0, "already-fitting no-op"
  var trim = limits
  trim.items = ElementLimit(0)
  trim.evictions = ElementLimit(4)
  assert fixture.source.admitRetained([], trim).value.cache.len == 0, "retention witness 163"
  let result = success.value.cache
  assert result.lookup(lightKey(0)).error == LightCacheError.UnknownKey, "retention witness 165"
  assert result.lookup(lightKey(64)).value.kind == StateLookupKind.Absent, "retention witness 166"
  assert result.lookup(lightKey(128)).value.kind == StateLookupKind.Present and result.lookup(
      lightKey(128)).value.bytes.len == 0, "retention witness 167"
  assert reader.lookup(lightKey(0)).value.bytes[0] == 7 and not cursor.finished, "retention witness 169"
  let limited = rootFixture(ElementLimit(1))
  resetHash(0)
  assert limited.source.admitRetained([evidence[2]], limits).error ==
      LightSnapshotError.LimitExceeded, "retention witness 172"
  assert limited.source.admitRetained([evidence[0]], limits).error == LightSnapshotError.None, "protected replacement needs no removal"
  let readOnly = rootFixture(ElementLimit(0))
  resetHash(0)
  assert readOnly.source.admitRetained([], limits).value.encodedBytes == original, "retention witness 177"
  assert readOnly.source.admitRetained([], trim).error == LightSnapshotError.LimitExceeded and
      calls() == 0, "retention witness 178"
  for index in 0..<10: cycle(fixture, evidence[2], limits)
  let before = getOccupiedMem()
  for index in 0..<1000: cycle(fixture, evidence[2], limits)
  let after = getOccupiedMem()
  assert before == after, "retention plans and refused updates retire completely"
  recordArcRelease("storage_light_retention", 1000, before, after)
  assert fixture.source.encodedBytes == original, "retention witness 186"
let fixture = rootFixture(ElementLimit(8))
let evidence = inputs(fixture)
modelCases(fixture, evidence)
boundaries(fixture, evidence)
resetHash(0)
echo "PASS light retention: independent quota model, protected incoming queries, atomic proof failures and immutable readers"
