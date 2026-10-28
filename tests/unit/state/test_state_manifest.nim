# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete-map service declarations require exact source bytes and preserve immutable provenance.
# @@Verification={"arc": "state_manifest_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/testing_arc_evidence
import ../../../src/state/global_snapshot as state_global_snapshot
import ../../../src/state/manifest as state_manifest
import ../../../src/state/store as state_store
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
  ## Refuse hashing only for preflight or explicit backend rollback witnesses.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count every attempted backend hash independently of result classification.
const
  profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), epochSlots: EpochSlots(2))
  globalLimits = GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
    maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))
  limits = StateManifestLimits(services: ElementLimit(4), storageKeyBytes: ByteLimit(32),
    serialized: StateTrieLimits(items: ElementLimit(64), nodes: TrieNodeLimit(1024),
      perValue: ByteLimit(65536), totalValueBytes: ByteLimit(262144)))
  stores = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(64),
    nodes: TrieNodeLimit(1024), perValue: ByteLimit(65536),
    totalValueBytes: ByteLimit(262144)), writes: ElementLimit(64),
    writeValueBytes: ByteLimit(262144))
proc globals(entries: seq[StateEntry]): ValidatedGlobalState =
  ## Retire temporary store/snapshot handles and return only genuinely validated complete-source globals.
  let source = newStateStore(entries, stores).value.snapshot.value
  validateGlobalState(source, profile, globalLimits).value
proc cycle(source: ValidatedGlobalState, services: seq[StateService]) =
  ## Retire complete matching and refusal graphs inside one activation before observing allocator occupancy.
  let completed = validateStateManifest(source, services, limits).value
  assert sameStateSnapshot(completed.manifestSource.value, source.globalSource.value)
  assert completed.manifestInfo.value.services == 2
  assert validateStateManifest(source, [], limits).error == StateManifestError.MappingMismatch
proc main() {.raises.} =
  ## Use independent global fixture bytes and lower-level service entry constructors as the source oracle.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var entries: seq[StateEntry] = @[]
  for i in 1..16:
    entries.add(StateEntry(key: chapterKey(StateChapter(i)), value: fixture[
        i-1])) # Existing typed composition is not used to build the source mapping.
  var preimage = default(array[32, byte])
  var request = default(array[32, byte])
  preimage[0] = 31
  request[0] = 42
  let hash = ServicePreimageHash(preimage)
  let requestHash = ServicePreimageHash(request)
  let service = ServiceIndex(7)
  var services = @[
    StateService(service: service, metadata: ServiceMetadata(balance: AccountBalance(99)),
      storage: @[StateStorageItem(key: @[byte(3), 1], value: @[byte(4), 5])],
      preimages: @[StatePreimageItem(hash: hash, value: @[byte(9)])],
      requests: @[StateRequestItem(hash: requestHash, length: RequestLength(0xfffffffd'u32),
        history: reavailableHistory(RequestSlot(0), RequestSlot(1), RequestSlot(high(uint32))))]),
    StateService(service: ServiceIndex(8), metadata: default(ServiceMetadata),
      storage: @[StateStorageItem(key: @[], value: @[])])]
  for item in services:
    entries.add(serviceMetadataEntry(item.service, item.metadata, ByteLimit(105)).value)
    for value in item.storage:
      entries.add(serviceStorageEntry(item.service, value.key, value.value,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(65536))).value)
    for value in item.preimages:
      entries.add(servicePreimageEntry(item.service, value.hash, value.value,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(65536))).value)
    for value in item.requests:
      entries.add(serviceRequestEntry(item.service, value.hash, value.length, value.history,
        RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
          items: ElementLimit(3), maxBytes: ByteLimit(13)))).value)
  let source = globals(entries)
  let original = source.globalSource.value
  let complete = validateStateManifest(source, services, limits).value
  assert sameStateSnapshot(complete.manifestSource.value, original)
  assert sameStateSnapshot(complete.manifestGlobals.value.globalSource.value, original)
  assert complete.manifestInfo.value.entries == entries.len
  assert complete.manifestInfo.value.services == 2
  var reversed = @[services[1], services[0]]
  assert validateStateManifest(source, reversed, limits).error == StateManifestError.None
  var total = 0'u64
  var maximum = 0'u64
  for entry in entries:
    total += uint64(entry.value.len)
    maximum = max(maximum, uint64(entry.value.len))
  assert complete.manifestInfo.value.valueBytes == total
  var exact = limits
  exact.services = ElementLimit(2)
  exact.storageKeyBytes = ByteLimit(2)
  exact.serialized.items = ElementLimit(uint64(entries.len))
  exact.serialized.nodes = TrieNodeLimit(original.commitment.nodes)
  exact.serialized.perValue = ByteLimit(maximum)
  exact.serialized.totalValueBytes = ByteLimit(total)
  assert validateStateManifest(source, services, exact).error == StateManifestError.None
  fail(1)
  var short = exact
  short.services = ElementLimit(1)
  assert validateStateManifest(source, services, short).error == StateManifestError.LimitExceeded
  short = exact
  short.serialized.items = ElementLimit(uint64(entries.len-1))
  assert validateStateManifest(source, services, short).error == StateManifestError.LimitExceeded
  short = exact
  short.serialized.nodes = TrieNodeLimit(original.commitment.nodes-1)
  assert validateStateManifest(source, services, short).error == StateManifestError.LimitExceeded
  short = exact
  short.serialized.perValue = ByteLimit(maximum-1)
  assert validateStateManifest(source, services, short).error == StateManifestError.LimitExceeded
  short = exact
  short.serialized.totalValueBytes = ByteLimit(total-1)
  assert validateStateManifest(source, services, short).error == StateManifestError.LimitExceeded
  short = exact
  short.storageKeyBytes = ByteLimit(1)
  let keyLimit = validateStateManifest(source, services, short)
  assert keyLimit.error == StateManifestError.CompositionFailure
  assert keyLimit.compositionError == StateCompositionError.LimitExceeded
  assert calls() == 0 # Every independent short source or raw-key policy refuses before hashing.
  let backend = validateStateManifest(source, services, limits)
  assert backend.error == StateManifestError.CompositionFailure
  assert backend.compositionError == StateCompositionError.BackendFailure
  assert calls() > 0
  fail(0)
  assert validateStateManifest(default(ValidatedGlobalState), services, limits).error ==
      StateManifestError.InvalidSource
  assert default(ValidatedStateManifest).manifestSource.error == StateManifestError.Uninitialized
  assert default(ValidatedStateManifest).manifestGlobals.error == StateManifestError.Uninitialized
  assert default(ValidatedStateManifest).manifestInfo.error == StateManifestError.Uninitialized
  assert validateStateManifest(source, [], limits).error == StateManifestError.MappingMismatch
  assert validateStateManifest(source, [services[0]], limits).error ==
      StateManifestError.MappingMismatch
  let duplicates = validateStateManifest(source, [services[0], services[0]], limits)
  assert duplicates.error == StateManifestError.CompositionFailure
  assert duplicates.compositionError == StateCompositionError.DuplicateKey
  var opaque = services
  opaque[0].captured = @[captureServiceValue(service, entries[17].key, entries[17].value,
    ByteLimit(65536)).value]
  fail(1)
  assert validateStateManifest(source, opaque, limits).error == StateManifestError.OpaqueValues
  assert calls() == 0 # Even a matching raw physical key does not supply a logical namespace declaration.
  fail(0)
  for reserved in [0xfffffffe'u32, 0xffffffff'u32]:
    var invalid = services
    invalid[0].requests[0].length = RequestLength(reserved)
    let refused = validateStateManifest(source, invalid, limits)
    assert refused.error == StateManifestError.CompositionFailure
    assert refused.compositionError == StateCompositionError.InvalidComponent # Current PR542 bounds never fall back to the historical namespace.
  var changed = entries
  changed[17].value = @[byte(4), 6] # Equal-length storage replacement must fail an actual byte comparison.
  let altered = globals(changed)
  assert validateStateManifest(altered, services, limits).error ==
      StateManifestError.MappingMismatch
  changed = entries
  changed[17].key = chapterKey(StateChapter(99)) # Same-count different keys cannot satisfy exact coverage.
  let substituted = globals(changed)
  assert validateStateManifest(substituted, services, limits).error ==
      StateManifestError.MappingMismatch
  changed = entries
  changed.delete(17)
  assert validateStateManifest(globals(changed), services, limits).error ==
      StateManifestError.MappingMismatch
  changed = entries
  changed.add(StateEntry(key: chapterKey(StateChapter(99)), value: @[]))
  assert validateStateManifest(globals(changed), services, limits).error ==
      StateManifestError.MappingMismatch
  var onlyGlobal: seq[StateEntry] = @[]
  for i in 0..<16: onlyGlobal.add(entries[i]) # Explicit empty service manifests cover only genuinely global-only maps.
  assert validateStateManifest(globals(onlyGlobal), [], limits).error == StateManifestError.None
  reversed[0].storage[0].value = @[byte(1)]
  assert sameStateSnapshot(complete.manifestSource.value,
      original) # Retained success does not borrow caller descriptors.
  assert complete.manifestSource.value.lookup(entries[21].key).value.byteLength == 0
  for i in 0..<25: cycle(source, services) # Warm both complete and failed temporary graphs before measuring ARC.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source, services) # Composition temporaries retire without being retained by the final certificate.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_manifest", 1000, before, after)
  echo "state-manifest: ok"
try:
  main()
except:
  quit(2) # Fixture, compiler or setup errors cannot count as successful state validation.
