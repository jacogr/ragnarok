# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frame-sized strict reopen matches whole-buffer admission over every valid prefix, byte mutation and observed IO refusal.
# @@Verification={"arc":"storage_light_streaming_reopen_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, storage_io, storage_light_journal]
import ../../../src/storage/light/journal/[cache as light_journal_cache,
    replay as light_journal_replay, manifest as light_journal_manifest]
import ../../../src/storage/light/[delta as light_delta, snapshot as light_snapshot,
    state_cache as light_state_cache]
import ../../../src/storage/state_proof
import ../../../src/storage/managed/[io as managed_io, manifest as managed_manifest]
import ../../../src/storage/file/errors as file_errors
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
proc joined(anchor: seq[byte], one, two: PreparedLightDelta, cut: int): seq[byte] =
  ## Independently concatenate a complete first frame and an explicitly selected second-frame prefix.
  result = anchor
  for octet in one.encodedBytes: result.add(octet)
  for index in 0..<cut: result.add(two.encodedBytes[index])
func expectedFile(outcome: LightReplayResult[LightJournalReplay]): FileError =
  ## The documented storage translation preserves identity, stale-position, policy/provider and incomplete distinctions.
  case outcome.error
  of LightReplayError.None: FileError.None
  of LightReplayError.LimitExceeded, LightReplayError.SequenceExhausted: FileError.LimitExceeded
  of LightReplayError.BackendFailure: FileError.BackendFailure
  of LightReplayError.WrongCheckpoint: FileError.WrongIdentity
  of LightReplayError.InvalidDelta:
    case outcome.deltaError
    of LightDeltaError.LimitExceeded, LightDeltaError.LengthOverflow: FileError.LimitExceeded
    of LightDeltaError.WrongChain, LightDeltaError.WrongRoot: FileError.WrongIdentity
    of LightDeltaError.WrongBase, LightDeltaError.WrongSequence: FileError.StaleView
    of LightDeltaError.BackendFailure: FileError.BackendFailure
    else: FileError.InvalidBatch
  else: FileError.InvalidJournal
proc checkInput(path: string, input: seq[byte], fixture: LightJournalFixture,
    manifest: LightJournalManifest) {.raises.} =
  ## The filesystem consumer independently segments the same bytes and must preserve exact forensic input on every verdict.
  var owner = default(LightJournalCache)
  defer:
    resetIo()
    if owner.opened: discard owner.close
  writeFile(lightChild(path, ManagedFileKind.Journal), lightText(input))
  let whole = replayLightJournal(input, manifest, fixture.initial, fixture.config.journal)
  resetIo()
  let opened = openLightJournalCache(owner, path, fixture.config)
  if opened != expectedFile(whole): echo "streaming verdict mismatch ", input.len, " ", opened, " ", whole.error
  assert opened == expectedFile(whole), "streaming and whole-buffer admission differ"
  assert ioCalls(writeIo) == 0 and ioCalls(renameIo) == 0 and ioCalls(unlinkIo) == 0, "strict reopen changes no namespace bytes"
  if opened == FileError.None:
    assert owner.preparedSnapshot.value.bytes == whole.value.snapshot.bytes, "exact whole-buffer successor"
    assert uint64(owner.sequence.value) == uint64(whole.value.sequence), "exact whole-buffer sequence"
    let retained = owner.preparedSnapshot.value
    let reader = owner.snapshot.value
    assert owner.close == FileError.None, "retire confirmed stream owner"
    assert retained.encodedBytes == whole.value.snapshot.encodedBytes, "anchor or successor survives private checkpoint scope and native close"
    for first in [0'u8, 255'u8]:
      # Both present and authenticated-absence results belong to retained immutable evidence, not the retired checkpoint locals.
      let found = reader.lookup(lightKey(first))
      let expected = whole.value.snapshot.cache.lookup(lightKey(first))
      assert found.error == expected.error, "retained stream reader preserves knowledge"
      if found.error == LightCacheError.None:
        assert found.value.kind == expected.value.kind, "retained stream reader preserves presence and absence"
        if found.value.kind == StateLookupKind.Present:
          assert found.value.bytes == expected.value.bytes, "retained stream values outlive native owner"
  else:
    assert not owner.opened, "refused stream publishes no owner"
  assert readFile(lightChild(path, ManagedFileKind.Journal)) == lightText(input), "strict read preserves exact journal bytes"
proc openCycle(path: string, fixture: LightJournalFixture) =
  ## Native owners, immutable prefixes, frame buffers and result temporaries retire before the next memory sample.
  var owner = default(LightJournalCache)
  assert openLightJournalCache(owner, path, fixture.config) == FileError.None, "strict cycle reopen"
  assert uint64(owner.sequence.value) == 2, "strict cycle sequence"
  let retained = owner.preparedSnapshot.value
  assert owner.close == FileError.None, "strict cycle retirement"
  assert retained.encodedBytes == fixture.following.snapshot.encodedBytes, "scoped replay successor survives owner retirement"
proc main() {.raises.} =
  ## Independently authored fixture transitions anchor exact progress, malformed boundaries and all actual native read/barrier refusals.
  let fixture = lightFixture()
  let path = "light-streaming-reopen-" & $storageProcessId()
  seedLightJournal(path, fixture)
  let manifest = prepareLightJournalManifest(fixture.initial, ManagedEpoch(1), LightDeltaSequence(
      0), ByteLimit(171)).value
  let anchor = encodeLightJournalAnchor(manifest, ByteLimit(98)).value
  let started = beginLightJournalReplay(anchor, manifest, fixture.initial,
      fixture.config.journal).value
  assert started.frameCount == 0 and uint64(started.sequence) == 0, "anchor grants only checkpoint prefix"
  let first = advanceLightJournalReplay(started, fixture.next.encodedBytes,
      fixture.config.journal).value
  let final = advanceLightJournalReplay(first, fixture.following.encodedBytes,
      fixture.config.journal).value
  assert final.snapshot.bytes == fixture.following.snapshot.bytes and final.frameCount == 2, "exact frame-by-frame successor"
  assert started.snapshot.bytes == fixture.initial.bytes and first.snapshot.bytes ==
      fixture.next.snapshot.bytes, "retained prefix readers remain immutable"
  assert advanceLightJournalReplay(default(LightJournalReplay), [], fixture.config.journal).error ==
      LightReplayError.Uninitialized, "default prefix refuses advance"
  let declared = lightDeltaDeclaredExtent(fixture.next.encodedBytes.toOpenArray(0, 175),
      fixture.config.journal.frame)
  assert declared.value == fixture.next.byteLength, "fixed header sizes one bounded future allocation"
  assert lightDeltaExtent(fixture.next.encodedBytes.toOpenArray(0, 175),
      fixture.config.journal.frame).error == LightDeltaError.IncompleteFrame, "declared extent is not complete-frame authority"
  var extra = fixture.next.bytes
  extra.add(0)
  let trailing = advanceLightJournalReplay(started, extra, fixture.config.journal)
  assert trailing.error == LightReplayError.InvalidDelta and trailing.deltaError ==
      LightDeltaError.InvalidFormat, "one step cannot consume a following suffix"
  var clipped = fixture.config.journal
  clipped.frames = ElementLimit(0)
  assert advanceLightJournalReplay(started, fixture.next.encodedBytes, clipped).error ==
      LightReplayError.LimitExceeded, "frame cap precedes verification"
  clipped = fixture.config.journal
  clipped.bytes = ByteLimit(98)
  assert advanceLightJournalReplay(started, fixture.next.encodedBytes, clipped).error ==
      LightReplayError.LimitExceeded, "aggregate byte cap includes authenticated anchor"
  var empty = newSeq[byte](0)
  checkInput(path, empty, fixture, manifest)
  for cut in 0..<anchor.len:
    # Every short anchor refuses; zero-length and nonempty windows must never index an absent byte.
    var partial = newSeq[byte](cut)
    for index in 0..<cut: partial[index] = anchor[index]
    checkInput(path, partial, fixture, manifest)
  checkInput(path, anchor, fixture, manifest)
  for cut in 0..fixture.following.byteLength:
    # Every valid second-frame prefix retains the first authenticated frame but cannot make strict open salvage a suffix.
    checkInput(path, joined(anchor, fixture.next, fixture.following, cut), fixture, manifest)
  let complete = joined(anchor, fixture.next, fixture.following, fixture.following.byteLength)
  for index in 0..<fixture.following.byteLength:
    # Every byte position in the second frame independently exercises header, payload and footer segmentation/refusal parity.
    var changed = joined(anchor, fixture.next, fixture.following, fixture.following.byteLength)
    let offset = anchor.len+fixture.next.byteLength+index
    changed[offset] = changed[offset] xor 1
    checkInput(path, changed, fixture, manifest)
  writeFile(lightChild(path, ManagedFileKind.Journal), lightText(complete))
  var owner = default(LightJournalCache)
  defer:
    resetIo()
    if owner.opened: discard owner.close
  resetIo()
  assert openLightJournalCache(owner, path, fixture.config) == FileError.None, "observe completed stream read family"
  let reads = ioCalls(readIo)
  assert reads > 4 and reads < 128, "bounded real read count"
  assert owner.close == FileError.None, "retire completed control"
  for operation in [readIo, syncIo]:
    let count = if operation == readIo: reads else: 2'u64
    for skip in 0..<int(count):
      # Each actual IO position must consume its refusal, publish no owner and release all native leases.
      resetIo()
      armIo(operation, cint(skip), 1, failedIo)
      assert openLightJournalCache(owner, path, fixture.config) == FileError.IoFailure, "typed stream IO refusal"
      assert pendingIo() == 0 and not owner.opened, "consume failure without owner publication"
      resetIo()
      var lease = default(ManagedDirectory)
      assert openManagedDirectory(lease, path) == FileError.None, "refused stream releases lease"
      assert lease.close == FileError.None, "explicit refusal lease retirement"
      assert readFile(lightChild(path, ManagedFileKind.Journal)) == lightText(complete), "IO refusal preserves forensic journal"
  resetIo()
  limitReads(7)
  assert openLightJournalCache(owner, path, fixture.config) == FileError.None, "strict stream tolerates genuine short native reads"
  assert owner.preparedSnapshot.value.bytes == fixture.following.snapshot.bytes, "short-read stream confirms exact image"
  resetIo()
  assert owner.close == FileError.None, "retire short-read owner"
  for index in 0..<10: openCycle(path, fixture)
  let before = getOccupiedMem()
  for index in 0..<1000: openCycle(path, fixture)
  let after = getOccupiedMem()
  assert before == after, "stream frames and owners retire without predecessor chains"
  recordArcRelease("storage_light_streaming_reopen", 1000, before, after)
  retireLightJournal(path)
try:
  main()
except:
  quit(2)
echo "PASS light streaming reopen: bounded frames, every prefix and byte mutation, whole-buffer parity, IO refusal and ARC retirement"
