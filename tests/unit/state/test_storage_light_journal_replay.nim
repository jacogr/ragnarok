# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Journal replay authenticates exact ordered transitions and gives explicit partial-tail plans no mutable authority.
# @@Verification={"arc":"storage_light_journal_replay_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/storage/light/journal/[replay as light_journal_replay,
    manifest as light_journal_manifest]
import ../../../src/storage/light/[delta as light_delta, snapshot as light_snapshot,
    state_cache as light_state_cache]
import ../../../src/storage/[state_proof, database_identity]
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/crypto/primitives
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## The provider observer isolates verification refusal and preflight work.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Every observed replay hash boundary must independently refuse without publication.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Structural and policy refusals are checked before provider calls where applicable.
proc policy(): LightSnapshotLimits =
  ## An independently trusted empty complete root admits only genuine absence evidence.
  LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(items: ElementLimit(4),
    writes: ElementLimit(4), valueBytes: ByteLimit(128), proof: StateProofLimits(
        nodes: ElementLimit(249), valueBytes: ByteLimit(32))))
proc bounds(): LightReplayLimits =
  ## Total bytes, frame count and per-frame limits each have distinct boundary witnesses.
  LightReplayLimits(bytes: ByteLimit(4096), frames: ElementLimit(4),
    frame: LightDeltaLimits(items: ElementLimit(4), bytes: ByteLimit(1024)))
proc first(input: seq[byte], size: int): seq[byte] =
  ## Copy only a proved prefix; the pinned stdlib's sequence slicing helper is unsupported.
  assert size >= 0 and size <= input.len, "replay witness 29"
  result = newSeq[byte](size)
  for index in 0..<size: result[index] = input[index]
proc join(left, right: seq[byte]): seq[byte] =
  ## Small fixed test fixtures prove native capacity before concatenation.
  assert right.len <= high(int)-left.len, "replay witness 34"
  result = newSeq[byte](left.len+right.len)
  for index in 0..<left.len: result[index] = left[index]
  for index in 0..<right.len: result[left.len+index] = right[index]
proc put(input: var seq[byte], offset: int, value: uint64) =
  ## Independent malformed-fixture editing preserves exact known little-endian widths.
  for index in 0..<8: input[offset+index] = byte((value shr (8*index)) and 255)
proc seal(input: var seq[byte]) =
  ## A valid local checksum cannot grant an invalid proof or transition authority.
  resetHash(0)
  let checksum = array[32, byte](blake2b256(input.toOpenArray(0, input.len-33)).value)
  for index in 0..<32: input[input.len-32+index] = checksum[index]
proc cycle(image: PreparedLightSnapshot, manifest: LightJournalManifest, complete, partial: seq[byte]) =
  ## Retire complete and explicit-prefix readers, plans, provider failures and exact revalidation together.
  resetHash(0)
  let replayed = replayLightJournal(complete, manifest, image, bounds()).value
  assert uint64(replayed.sequence) == 3 and replayed.frameCount == 3, "replay witness 50"
  let planned = planLightJournalTail(partial, manifest, image, bounds()).value
  assert planned.prefix.frameCount == 2 and uint64(planned.prefix.sequence) == 2, "replay witness 52"
  assert validateLightTailPlan(partial, manifest, planned) == LightReplayError.None, "replay witness 53"
  refuseAfter(1)
  let refused = replayLightJournal(complete, manifest, image, bounds())
  assert refused.error != LightReplayError.None, "replay witness 56"
  resetHash(0)
  let retried = replayLightJournal(complete, manifest, image, bounds()).value
  assert retried.snapshot.bytes == replayed.snapshot.bytes, "replay witness 59"
proc main() =
  ## Three genuine proof-cache transitions establish exact predecessor, ordering, suffix and plan boundaries.
  let image = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [], policy()).value
  let absent = LightStateProof(key: default(StateKey), proof: StateProof(nodes: @[], value: @[]))
  let manifest = prepareLightJournalManifest(image, ManagedEpoch(1), LightDeltaSequence(0),
      ByteLimit(171)).value
  let anchor = encodeLightJournalAnchor(manifest, ByteLimit(98)).value
  let one = prepareLightDelta(image, LightDeltaSequence(1), [absent], [], bounds().frame).value
  let two = prepareLightDelta(one.snapshot, LightDeltaSequence(2), [], [absent.key], bounds().frame).value
  let three = prepareLightDelta(two.snapshot, LightDeltaSequence(3), [absent], [], bounds().frame).value
  let prefixBytes = join(join(anchor, one.bytes), two.bytes)
  let complete = join(prefixBytes, three.bytes)
  let partial = join(prefixBytes, first(three.bytes, three.byteLength-1))
  let replayed = replayLightJournal(complete, manifest, image, bounds()).value
  assert replayed.initialized and replayed.frameCount == 3 and uint64(replayed.sequence) == 3, "replay witness 74"
  assert replayed.byteLength == complete.len and replayed.snapshot.bytes == three.snapshot.bytes, "replay witness 75"
  assert replayed.snapshot.cache.lookup(absent.key).error == LightCacheError.None, "replay witness 76"
  assert image.cache.lookup(absent.key).error == LightCacheError.UnknownKey, "replay witness 77"
  assert not default(LightJournalReplay).initialized and not default(LightTailPlan).initialized, "replay witness 78"
  let empty = replayLightJournal(anchor, manifest, image, bounds()).value
  assert empty.frameCount == 0 and uint64(empty.sequence) == 0 and empty.snapshot.bytes ==
      image.bytes, "replay witness 80"
  assert planLightJournalTail(complete, manifest, image, bounds()).error ==
      LightReplayError.NotIncomplete, "replay witness 81"
  for size in 1..<three.byteLength:
    # Every valid nonempty proper frame prefix yields no strict success and one explicitly bounded discard plan.
    let input = join(prefixBytes, first(three.bytes, size))
    assert replayLightJournal(input, manifest, image, bounds()).error ==
        LightReplayError.IncompleteTail, "replay witness 86"
    let plan = planLightJournalTail(input, manifest, image, bounds()).value
    assert plan.initialized and plan.prefix.byteLength == prefixBytes.len and plan.totalBytes ==
        input.len, "replay witness 89"
    assert plan.prefix.snapshot.bytes == image.bytes and plan.prefix.frameCount == 2, "replay witness 90"
    assert uint64(plan.prefix.sequence) == 2, "replay witness 91"
    assert array[32, byte](plan.selectionChecksum) == array[32, byte](manifest.checksum), "replay witness 92"
    assert validateLightTailPlan(input, manifest, plan) == LightReplayError.None, "replay witness 93"
  for size in 0..<anchor.len:
    # An incomplete journal anchor never grants even zero-frame repair authority.
    let input = first(anchor, size)
    assert replayLightJournal(input, manifest, image, bounds()).error ==
        LightReplayError.InvalidFormat, "replay witness 97"
    assert planLightJournalTail(input, manifest, image, bounds()).error ==
        LightReplayError.InvalidFormat, "replay witness 99"
  let plan = planLightJournalTail(partial, manifest, image, bounds()).value
  var changed = partial
  changed[changed.len-1] = changed[changed.len-1] xor 1
  assert validateLightTailPlan(changed, manifest, plan) == LightReplayError.ChangedInput, "replay witness 104"
  changed = partial
  changed.add(0)
  assert validateLightTailPlan(changed, manifest, plan) == LightReplayError.ChangedInput, "replay witness 107"
  assert validateLightTailPlan(first(partial, partial.len-1), manifest, plan) ==
      LightReplayError.ChangedInput, "replay witness 108"
  let other = prepareLightJournalManifest(image, ManagedEpoch(2), LightDeltaSequence(0), ByteLimit(171)).value
  assert validateLightTailPlan(partial, other, plan) == LightReplayError.ChangedInput, "replay witness 111"
  assert validateLightTailPlan(partial, manifest, default(LightTailPlan)) ==
      LightReplayError.Uninitialized, "replay witness 112"
  let wrongCheckpoint = replayLightJournal(complete, manifest, one.snapshot, bounds())
  assert wrongCheckpoint.error == LightReplayError.WrongCheckpoint, "replay witness 115"
  let wrongAnchor = replayLightJournal(complete, other, image, bounds())
  assert wrongAnchor.error == LightReplayError.InvalidSelection, "replay witness 117"
  assert wrongAnchor.selectionError == LightSelectionError.WrongAnchor, "replay witness 118"
  let stale = replayLightJournal(join(join(anchor, one.bytes), one.bytes), manifest, image, bounds())
  assert stale.error == LightReplayError.InvalidDelta and stale.deltaError ==
      LightDeltaError.WrongBase, "replay witness 120"
  var damaged = three.bytes
  damaged[damaged.len-1] = damaged[damaged.len-1] xor 1
  let corrupt = planLightJournalTail(join(prefixBytes, damaged), manifest, image, bounds())
  assert corrupt.error == LightReplayError.InvalidDelta and corrupt.deltaError ==
      LightDeltaError.ChecksumMismatch, "replay witness 125"
  damaged = three.bytes
  damaged[120] = damaged[120] xor 1
  seal(damaged)
  let wrongSuccessor = planLightJournalTail(join(prefixBytes, damaged), manifest, image, bounds())
  assert wrongSuccessor.error == LightReplayError.InvalidDelta and wrongSuccessor.deltaError ==
      LightDeltaError.InvalidTransition, "replay witness 131"
  var badProof = newSeq[byte](three.byteLength+1)
  for index in 0..<three.byteLength-32: badProof[index] = three.encodedBytes[index]
  badProof[three.byteLength-32] = 1
  put(badProof, 168, 43)
  put(badProof, 210, 1)
  seal(badProof)
  let invalidProof = planLightJournalTail(join(prefixBytes, badProof), manifest, image, bounds())
  assert invalidProof.error == LightReplayError.InvalidDelta and invalidProof.deltaError ==
      LightDeltaError.ProofFailure, "invalid proof outer=" & $invalidProof.error & " inner=" &
          $invalidProof.deltaError
  for offset in [24, 56, 88, 152, 207]:
    # Known identity/base/sequence and partial tag errors cannot masquerade as unfinished transport.
    damaged = first(three.bytes, 208)
    damaged[offset] = damaged[offset] xor 2
    let invalid = planLightJournalTail(join(prefixBytes, damaged), manifest, image, bounds())
    assert invalid.error == LightReplayError.InvalidDelta, "replay witness 147"
  damaged = first(three.bytes, 220)
  damaged[176] = 1
  damaged[218] = damaged[218] xor 1
  let partialFooter = planLightJournalTail(join(prefixBytes, damaged), manifest, image, bounds())
  assert partialFooter.error == LightReplayError.InvalidDelta and partialFooter.deltaError ==
      LightDeltaError.ChecksumMismatch, "replay witness 152"
  for mode in 0..<5:
    # Incomplete count/length/node/reserved fields and impossible body padding already prove invalidity.
    damaged = first(three.bytes, 218)
    case mode
    of 0:
      damaged = first(damaged, 161)
      damaged[160] = 5
    of 1:
      damaged = first(damaged, 170)
      damaged[168] = 255
      damaged[169] = 255
    of 2:
      damaged = first(damaged, 210)
      damaged[208] = 250
    of 3:
      damaged[207] = 0
      damaged[210] = 1
    else:
      damaged[168] = 43
    let invalid = planLightJournalTail(join(prefixBytes, damaged), manifest, image, bounds())
    assert invalid.error == LightReplayError.InvalidDelta, "partial structural refusal"
  var secondKey = default(array[31, byte])
  secondKey[0] = 1
  let second = LightStateProof(key: StateKey(secondKey), proof: StateProof(nodes: @[], value: @[]))
  let pair = prepareLightDelta(image, LightDeltaSequence(1), [absent, second], [], bounds().frame).value
  damaged = first(pair.bytes, 249)
  for index in 218..<249: damaged[index] = 0
  let duplicate = planLightJournalTail(join(anchor, damaged), manifest, image, bounds())
  assert duplicate.error == LightReplayError.InvalidDelta and duplicate.deltaError ==
      LightDeltaError.InvalidFormat, "partial duplicate key"
  damaged = first(pair.bytes, 248)
  for index in 176..<207: damaged[index] = 255
  for index in 218..<248: damaged[index] = 255
  let impossible = planLightJournalTail(join(anchor, damaged), manifest, image, bounds())
  assert impossible.error == LightReplayError.InvalidDelta and impossible.deltaError ==
      LightDeltaError.InvalidFormat, "no greater partial key completion"
  var limited = bounds()
  limited.bytes = ByteLimit(complete.len-1)
  assert replayLightJournal(complete, manifest, image, limited).error ==
      LightReplayError.LimitExceeded, "replay witness 156"
  limited = bounds()
  limited.frames = ElementLimit(2)
  assert replayLightJournal(complete, manifest, image, limited).error ==
      LightReplayError.LimitExceeded, "replay witness 160"
  limited = bounds()
  limited.frame.bytes = ByteLimit(249)
  let tooLarge = replayLightJournal(complete, manifest, image, limited)
  assert tooLarge.error == LightReplayError.InvalidDelta and tooLarge.deltaError ==
      LightDeltaError.LimitExceeded, "replay witness 165"
  limited = bounds()
  limited.frames = ElementLimit(0)
  assert replayLightJournal(anchor, manifest, image, limited).error == LightReplayError.None, "replay witness 169"
  let maximum = prepareLightJournalManifest(image, ManagedEpoch(1), LightDeltaSequence(high(
      uint64)), ByteLimit(171)).value
  let endAnchor = encodeLightJournalAnchor(maximum, ByteLimit(98)).value
  assert uint64(replayLightJournal(endAnchor, maximum, image, bounds()).value.sequence) == high(
      uint64), "replay witness 173"
  assert replayLightJournal(join(endAnchor, one.bytes), maximum, image, bounds()).error ==
      LightReplayError.SequenceExhausted, "replay witness 174"
  assert replayLightJournal(complete, default(LightJournalManifest), image, bounds()).error ==
      LightReplayError.Uninitialized, "replay witness 176"
  resetHash(0)
  assert replayLightJournal(complete, manifest, image, bounds()).error == LightReplayError.None, "replay witness 179"
  let boundaries = calls()
  assert boundaries >= 0 and int64(boundaries) <= int64(high(cint)), "replay witness 181"
  assert boundaries > 3, "replay witness 182"
  for count in 0..<boundaries:
    # Every anchor, frame, proof and successor hash refusal preserves the old reader and grants no completed replay.
    refuseAfter(cint(count))
    assert replayLightJournal(complete, manifest, image, bounds()).error != LightReplayError.None, "replay witness 186"
  resetHash(0)
  assert planLightJournalTail(partial, manifest, image, bounds()).error == LightReplayError.None, "replay witness 188"
  let planning = calls()
  assert planning >= 0 and int64(planning) <= int64(high(cint)), "replay witness 190"
  for count in 0..<planning:
    # Planning also checks partial-footer and complete-transport hashes without granting partial plans on refusal.
    refuseAfter(cint(count))
    assert planLightJournalTail(partial, manifest, image, bounds()).error != LightReplayError.None, "replay witness 194"
  resetHash(1)
  assert validateLightTailPlan(partial, manifest, plan) == LightReplayError.BackendFailure, "replay witness 196"
  resetHash(0)
  assert image.cache.len == 0 and replayed.snapshot.bytes == three.snapshot.bytes, "replay witness 198"
  let occupied = getOccupiedMem()
  for index in 0..<1000:
    # All scopes retire before sampling; no replay or plan retains a predecessor image chain.
    cycle(image, manifest, complete, partial)
  recordArcRelease("storage_light_journal_replay", 1000, occupied, getOccupiedMem())
  echo "PASS light journal replay: strict bounded transitions, no corrupt-prefix salvage and exact-byte explicit tail plans"
main()
