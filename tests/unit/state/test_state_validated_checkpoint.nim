# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Existing checkpoint transport retains expected-root policy and precise typed serialization phases.
# @@Verification={"arc": "state_validated_checkpoint_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/testing_arc_evidence
import ../../../src/state/validated_checkpoint as state_validated_checkpoint
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/store as state_store
import ../../../src/state/global_snapshot as state_global_snapshot
import ../../../src/state/manifest as state_manifest
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_consensus as codec_state_consensus
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_requests as codec_state_requests
include ../../native/nimony_composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset the observer and optionally refuse every attempted state hash.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Measure the existing restoration hash count separately from typed validation.
proc after(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Permit a complete restoration, then refuse the first later manifest hash.
const
  profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), epochSlots: EpochSlots(2))
  mapLimits = StateTrieLimits(items: ElementLimit(64), nodes: TrieNodeLimit(1024),
    perValue: ByteLimit(65536), totalValueBytes: ByteLimit(262144))
  stores = StateStoreLimits(trie: mapLimits, writes: ElementLimit(64), writeValueBytes: ByteLimit(262144))
  limits = StateCheckpointLimits(checkpointBytes: ByteLimit(524288), store: stores,
    globals: GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
      maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144)),
    manifest: StateManifestLimits(services: ElementLimit(4), serialized: mapLimits,
      storageKeyBytes: ByteLimit(32)))
proc snapshotOf(entries: seq[StateEntry]): StateStoreSnapshot =
  ## Produce an actual complete snapshot under the same independent restoration resource ceilings.
  newStateStore(entries, stores).value.snapshot.value
proc fromEntries(entries: seq[StateEntry], services: seq[StateService]): ValidatedCheckpointResult =
  ## Encode deliberately valid envelopes around either valid or invalid typed state without bypassing root verification.
  let source = snapshotOf(entries)
  let wire = encodeFullCheckpoint(source, limits.checkpointBytes).value
  decodeValidatedCheckpoint(wire, source.commitment.root, services, profile, limits)
proc checkDetached(wire: seq[byte], root: StateRoot, services: seq[StateService]) =
  ## Use an independently allocated input, overwrite every byte and release it before reading restored state.
  var disposable = newSeq[byte](wire.len)
  for index in 0..<wire.len: disposable[index] = wire[
      index] # No surviving caller alias can keep a borrowed input buffer valid.
  let completed = decodeValidatedCheckpoint(disposable, root, services, profile, limits).value
  for index in 0..<disposable.len: disposable[index] = disposable[
      index] xor 255 # Overwrite both values and framing before buffer release.
  disposable = @[]
  assert encodeFullCheckpoint(completed.manifestSource.value, limits.checkpointBytes).value == wire
proc cycle(wire: seq[byte], root: StateRoot, services: seq[StateService]) =
  ## Retire successful restored graphs and late manifest refusals inside one activation.
  let completed = decodeValidatedCheckpoint(wire, root, services, profile, limits).value
  assert array[32, byte](completed.manifestSource.value.commitment.root) == array[32, byte](root)
  let refused = decodeValidatedCheckpoint(wire, root, [], profile, limits)
  assert refused.error == ValidatedCheckpointError.ManifestFailure
  assert refused.manifestFailure.error == StateManifestError.MappingMismatch
proc main() {.raises.} =
  ## Build original chapter bytes and independently encoded service rows before checkpoint serialization.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var entries: seq[StateEntry] = @[]
  for i in 1..16:
    entries.add(StateEntry(key: chapterKey(StateChapter(i)), value: fixture[
        i-1])) # Independent fixture framing remains unchanged.
  let id = ServiceIndex(7)
  let services = @[StateService(service: id, metadata: ServiceMetadata(balance: AccountBalance(9)),
    storage: @[StateStorageItem(key: @[byte(1)], value: @[])])]
  entries.add(serviceMetadataEntry(id, services[0].metadata, ByteLimit(105)).value)
  entries.add(serviceStorageEntry(id, @[byte(1)], [], ServiceEntryLimits(
    keyBytes: ByteLimit(32), valueBytes: ByteLimit(65536))).value)
  let source = snapshotOf(entries)
  let expected = source.commitment.root
  let wire = encodeFullCheckpoint(source, limits.checkpointBytes).value
  checkDetached(wire, expected, services)
  let restored = decodeValidatedCheckpoint(wire, expected, services, profile, limits)
  assert restored.error == ValidatedCheckpointError.None
  let completed = restored.value
  let retained = completed.manifestSource.value
  assert not sameStateSnapshot(retained, source) # Restoration owns a new complete map rather than claiming original process identity.
  assert sameStateSnapshot(retained, completed.manifestSource.value)
  assert encodeFullCheckpoint(retained, limits.checkpointBytes).value ==
      wire # No new or alternate checkpoint format.
  for entry in entries:
    assert retained.lookup(entry.key).value.bytes ==
        entry.value # Exact restored bytes include present-empty service storage.
  var copy = wire
  copy[0] = 0
  let malformed = decodeValidatedCheckpoint(copy, expected, services, profile, limits)
  assert malformed.error == ValidatedCheckpointError.CheckpointFailure
  assert malformed.checkpointError == CheckpointError.InvalidFormat
  copy = wire
  copy.setLen(copy.len-1)
  let truncated = decodeValidatedCheckpoint(copy, expected, services, profile, limits)
  assert truncated.error == ValidatedCheckpointError.CheckpointFailure
  assert truncated.checkpointError == CheckpointError.InvalidFormat
  var wrong = array[32, byte](expected)
  wrong[0] = wrong[0] xor 1
  let untrusted = decodeValidatedCheckpoint(wire, StateRoot(wrong), services, profile, limits)
  assert untrusted.error == ValidatedCheckpointError.CheckpointFailure
  assert untrusted.checkpointError == CheckpointError.RootMismatch # The embedded root does not replace caller authority.
  fail(1)
  var short = limits
  short.checkpointBytes = ByteLimit(uint64(wire.len-1))
  let fileLimit = decodeValidatedCheckpoint(wire, expected, services, profile, short)
  assert fileLimit.error == ValidatedCheckpointError.CheckpointFailure
  assert fileLimit.checkpointError == CheckpointError.LimitExceeded
  short = limits
  short.store.trie.items = ElementLimit(uint64(entries.len-1))
  let mapLimit = decodeValidatedCheckpoint(wire, expected, services, profile, short)
  assert mapLimit.error == ValidatedCheckpointError.CheckpointFailure
  assert mapLimit.checkpointError == CheckpointError.LimitExceeded
  assert calls() == 0 # Envelope/source count policy refuses before any state hashing.
  let early = decodeValidatedCheckpoint(wire, expected, services, profile, limits)
  assert early.error == ValidatedCheckpointError.CheckpointFailure
  assert early.checkpointError == CheckpointError.BackendFailure
  fail(0)
  let ordinary = decodeFullCheckpoint(wire, expected, stores, limits.checkpointBytes)
  assert ordinary.error == CheckpointError.None
  let decoderHashes = calls()
  assert decoderHashes > 0
  after(decoderHashes)
  let late = decodeValidatedCheckpoint(wire, expected, services, profile, limits)
  assert late.error == ValidatedCheckpointError.ManifestFailure
  assert late.manifestFailure.error == StateManifestError.CompositionFailure
  assert late.manifestFailure.compositionError == StateCompositionError.BackendFailure
  fail(0)
  short = limits
  short.globals.totalBytes = ByteLimit(0)
  let globalLimit = decodeValidatedCheckpoint(wire, expected, services, profile, short)
  assert globalLimit.error == ValidatedCheckpointError.GlobalFailure
  assert globalLimit.globalFailure.error == GlobalStateError.LimitExceeded
  short = limits
  short.manifest.services = ElementLimit(0)
  let manifestLimit = decodeValidatedCheckpoint(wire, expected, services, profile, short)
  assert manifestLimit.error == ValidatedCheckpointError.ManifestFailure
  assert manifestLimit.manifestFailure.error == StateManifestError.LimitExceeded
  let badProfile = decodeValidatedCheckpoint(wire, expected, services, default(StateProfile), limits)
  assert badProfile.error == ValidatedCheckpointError.GlobalFailure
  assert badProfile.globalFailure.error == GlobalStateError.ChapterFailure
  assert badProfile.globalFailure.chapterError == StateCompositionError.InvalidConfig
  var changed = entries
  changed.delete(0)
  let missing = fromEntries(changed, services)
  assert missing.error == ValidatedCheckpointError.GlobalFailure
  assert missing.globalFailure.error == GlobalStateError.MissingChapter
  assert missing.globalFailure.failedChapter == StateChapterId.Pools
  changed = entries
  changed[15].value = @[byte(0xff)]
  let badValue = fromEntries(changed, services)
  assert badValue.error == ValidatedCheckpointError.GlobalFailure
  assert badValue.globalFailure.error == GlobalStateError.ChapterFailure
  assert badValue.globalFailure.failedChapter == StateChapterId.Outputs
  assert badValue.globalFailure.chapterError == StateCompositionError.Truncated
  let undeclared = decodeValidatedCheckpoint(wire, expected, [], profile, limits)
  assert undeclared.error == ValidatedCheckpointError.ManifestFailure
  assert undeclared.manifestFailure.error == StateManifestError.MappingMismatch
  var opaque = services
  opaque[0].captured = @[captureServiceValue(id, entries[17].key, [], ByteLimit(0)).value]
  let unclassified = decodeValidatedCheckpoint(wire, expected, opaque, profile, limits)
  assert unclassified.error == ValidatedCheckpointError.ManifestFailure
  assert unclassified.manifestFailure.error == StateManifestError.OpaqueValues
  var reserved = services
  reserved[0].requests = @[StateRequestItem(length: RequestLength(high(uint32)),
    history: requestedHistory())]
  let invalid = decodeValidatedCheckpoint(wire, expected, reserved, profile, limits)
  assert invalid.error == ValidatedCheckpointError.ManifestFailure
  assert invalid.manifestFailure.error == StateManifestError.CompositionFailure
  assert invalid.manifestFailure.compositionError == StateCompositionError.InvalidComponent
  copy = @[]
  assert retained.lookup(entries[17].key).value.byteLength ==
      0 # Retained restored bytes borrow neither caller wire nor descriptors.
  for i in 0..<25: cycle(wire, expected, services) # Warm the actual complete restoration/late-refusal ownership workload.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(wire, expected, services) # Every restored and composed temporary retires inside the cycle.
  let afterBytes = getOccupiedMem()
  assert before == afterBytes
  recordArcRelease("state_validated_checkpoint", 1000, before, afterBytes)
  echo "state-validated-checkpoint: ok"
try:
  main()
except:
  quit(2) # Setup, read or compilation failures cannot supply passing checkpoint validation evidence.
