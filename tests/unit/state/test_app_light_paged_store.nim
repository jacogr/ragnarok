# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native light application ownership keeps trusted metadata, partial proofs and bounded retirement coherent across restart.
# @@Verification={"arc":"light_paged_store_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../support/storage_disk_history_context
import ../../support/app_checkpoint_context
import ../../support/storage_io
import ../../../src/app/light_store as app_light_store
import ../../../src/app/light_head as app_light_head
import ../../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../../src/app/checkpoint_trust as app_checkpoint_trust
import ../../../src/app/chain as app_chain
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/header as codec_header
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/crypto/primitives as crypto_primitives
import ../../../src/state/store as state_store
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/paged_proof_view as state_paged_proof_view
import ../../../src/storage/light_state_cache as storage_light_state_cache
import ../../../src/storage/paged_store as storage_paged_store
import ../../../src/storage/paged_codec as storage_paged_codec
import ../../../src/storage/paged_stream as storage_paged_stream
import ../../../src/storage/paged_io as storage_paged_io
import ../../../src/storage/durability as storage_durability
import ../../../src/storage/file_errors as storage_file_errors
proc headerWire(sourceBlock: BlockSnapshotResult): seq[byte] =
  ## Test-only complete snapshots supply independently chosen canonical header bytes, never partial-root inference.
  let selected = sourceBlock.value.header
  result = newSeq[byte](selected.headerInfo.value.consumed)
  assert encodeOwnedHeader(selected, result).error == HeaderError.None
proc trust(sourceBlock: BlockSnapshotResult): TrustedApplicationCheckpoint =
  ## Caller-selected identity/header inputs are captured before the light owner sees proof evidence.
  let owner = initApplicationChain(genesisView(sourceBlock)).value
  let identity = captureApplicationCheckpointIdentity(owner).value
  let encoded = encodeApplicationCheckpointIdentity(identity, ByteLimit(4096)).value
  let captured = captureCheckpointTrust(encoded, sourceBlock.headerWire, ByteLimit(1048576))
  assert captured.error == CheckpointTrustError.None
  captured.value
proc policy(sourceBlock: BlockSnapshotResult): LightHeadLimits =
  ## Active validator geometry is selected independently from complete genesis context, never inferred from fetch parameters or partial facts.
  LightHeadLimits(header: HeaderConfig(cores: sourceBlock.value.cores,
    authorValidators: sourceBlock.value.activeValidators, epochSlots: sourceBlock.value.epochSlots,
    maxBytes: ByteLimit(262144)), headers: ElementLimit(3), headerBytes: ByteLimit(1048576),
    view: ProofViewLimits(items: ElementLimit(16), valueBytes: ByteLimit(4194304)))
proc entries(snapshot: StateStoreSnapshot): seq[StateEntry] =
  ## An independent complete fixture map is used only to author genuine membership/absence proofs.
  result = @[]
  for index in 0..<snapshot.commitment.entries:
    let key = snapshot.keyAt(StateEntryIndex(index)).value
    result.add(StateEntry(key: key, value: snapshot.lookup(key).value.bytes))
proc batch(snapshot: StateStoreSnapshot, keys: openArray[StateKey],
    limits: StateStoreLimits): VerifiedStateProofBatch =
  ## Full fixture generation and exact-root verification precede every partial view used by the application API.
  let perProof = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(4194304))
  let aggregate = StateProofBatchLimits(items: ElementLimit(16), nodes: ElementLimit(4096),
      valueBytes: ByteLimit(4194304))
  let generated = generateStateProofs(snapshot.entries, keys, limits.trie, perProof, aggregate)
  assert generated.error == StateProofError.None
  var queries = newSeq[StateProofQuery](generated.value.len)
  for index in 0..<queries.len: queries[index] = generated.value.queryAt(
      index).value # Immutable raw witnesses carry no trust until verified.
  let checked = verifyStateProofs(queries, snapshot.commitment.root, perProof, aggregate)
  assert checked.error == StateProofError.None
  checked.value
func key(value: byte): StateKey =
  ## High-byte fixture keys distinguish genuine absent witnesses from unrequested unknown facts.
  var bytes = default(array[31, byte])
  for index in 0..<bytes.len: bytes[index] = value
  StateKey(bytes)
proc checksum(bytes: var seq[byte]) =
  ## Independent identity-frame oracle rehashes the documented fixed 206-byte payload after one deliberate scalar change.
  assert bytes.len == 238
  let hashed = blake2b256(bytes.toOpenArray(0, 205))
  assert hashed.error == CryptoError.None
  let digest = array[32, byte](hashed.value)
  for index in 0..<32: bytes[206+index] = digest[index]
proc rootTrust(original: TrustedApplicationCheckpoint,
    root: StateRoot): TrustedApplicationCheckpoint =
  ## Test-only operator posterior-root choice remains independent of the sealed header's prior root; no consensus certificate is claimed.
  var identity = encodeApplicationCheckpointIdentity(original.identity, ByteLimit(4096)).value
  let digest = array[32, byte](root)
  for index in 0..<32: identity[48+index] = digest[index]
  checksum(identity)
  var header = newSeq[byte](original.sealedHeaderLength)
  assert original.copySealedHeader(header)
  let captured = captureCheckpointTrust(identity, header, ByteLimit(1048576))
  assert captured.error == CheckpointTrustError.None
  captured.value
proc path(label: string): string =
  ## Every trial owns a fresh ignored process namespace.
  "light-paged-store-" & $storageProcessId() & "-" & label
proc limits(source: BlockSnapshotResult): LightPagedLimits =
  ## Finite native stream work and retention ceilings are independent from logical header/proof policy.
  let elements = ElementLimit(1000000)
  let bytes = ByteLimit(268435456)
  let work = PagedWorkLimits(ioCalls: elements, producerCalls: elements, pageHashes: elements,
    proofs: elements, nodes: elements, readBytes: bytes, writeBytes: bytes, valueBytes: bytes)
  result = default(LightPagedLimits)
  result.head = source.policy
  result.native.root = source.trust.identity.stateRoot
  result.native.limits = PagedStreamLimits(dataset: PagedLimits(entries: ElementLimit(16),
      bytes: bytes),
    workingBytes: ByteLimit(33554432), cachePages: ElementLimit(1), contextBytes: ByteLimit(
        4194304), work: work)
  result.native.limits.proof.nodes = ElementLimit(249)
  result.native.limits.proof.valueBytes = ByteLimit(4194304)
  result.contextBytes = ByteLimit(1048576)
  result.proofs.proof = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(4194304))
  result.proofs.batch = StateProofBatchLimits(items: ElementLimit(16), nodes: ElementLimit(4096),
      valueBytes: ByteLimit(4194304))
  result.proofs.view = source.policy.view
  result.proofs.work = work
  result.inventory = work
proc facts(fixture: DiskHistoryFixture, ordinal: int): VerifiedStateProofBatch =
  ## Only independent complete fixture snapshots author raw evidence; the light owner retains no complete store.
  batch(fixture.blocks[ordinal].value.stateSnapshot, [chapterKey(StateChapter(11)), key(255)],
      fixture.policy)
proc empty(source: BlockSnapshotResult): LightApplicationHead =
  ## Bootstrap knows no state facts until independently verified evidence is supplied.
  captureLightHead(source.trust, source.policy).value
proc noIo() =
  ## Passive dispatcher operations must not hide synchronous native work.
  for operation in [readIo, writeIo, syncIo, lockIo, closeIo, renameIo, unlinkIo]:
    assert ioCalls(operation) == 0 # Each syscall family remains independently observable.
proc check(snapshot: LightStorageSnapshot, count: int) =
  ## Missing witnesses never turn into authenticated absence, including after native close.
  assert snapshot.valid and snapshot.head.valid
  assert snapshot.head.proofView.len == count
  assert snapshot.head.proofView.lookup(key(254)).error == ProofViewError.MissingWitness
  if count > 0:
    # A successful absent lookup is available only after that exact query was supplied and verified.
    assert snapshot.head.proofView.lookup(chapterKey(StateChapter(11))).value.present
    assert not snapshot.head.proofView.lookup(key(255)).value.present
proc normal(fixture: DiskHistoryFixture) =
  ## Same-root enrichment and different-root header advancement publish coherent metadata/proof pairs with one bounded predecessor.
  let directory = path("normal")
  let initial = fixture.blocks[0]
  let selected = initial.limits
  let added = fixture.facts(0)
  var disk = default(LightPagedStore)
  var reader = default(PagedReader)
  let first = initializeLightPagedStore(disk, directory, initial.empty, selected).value
  check(first, 0)
  assert uint64(first.manifest.sequence) == 0 and uint64(first.manifest.epoch) == 1
  resetIo()
  let job = prepareLightProofMerge(disk.snapshot.value, added).value
  check(disk.snapshot.value, 0)
  assert not disk.retirementPending
  noIo()
  assert openPagedReader(reader, directory, selected.native).error == PagedNativeError.None
  let second = disk.commit(job).value
  check(second, 2)
  check(first, 0)
  assert uint64(second.manifest.sequence) == 1 and uint64(second.manifest.epoch) == 2
  assert disk.retirementPending
  let cleanup = disk.prepareLightRetirement.value
  assert disk.retire(cleanup).nativeFailure.fileError == FileError.Busy
  check(disk.snapshot.value, 2)
  resetIo()
  assert disk.commit(prepareLightProofMerge(second, added).value).error ==
      LightStoreError.RetirementPending
  assert disk.commit(job).error == LightStoreError.StaleView
  noIo()
  assert reader.close == FileError.None
  assert disk.retire(cleanup).error == LightStoreError.None and not disk.retirementPending
  resetIo()
  assert disk.retire(cleanup).error == LightStoreError.StaleView
  noIo()
  assert disk.synchronize.value == StorageDurability.FileAndDirectorySynced
  assert disk.close == FileError.None
  check(second, 2)
  let existing = initializeLightPagedStore(disk, directory, initial.empty, selected)
  assert existing.error == LightStoreError.NativeFailure
  assert existing.nativeFailure.error == PagedNativeError.FileFailure and
    existing.nativeFailure.fileError == FileError.AlreadyExists # An unopened writer owns no close; preserve the exact refusal needed by strict startup selection.
  let missing = openLightPagedStore(disk, path("missing-open"), initial.trust, selected)
  assert missing.error == LightStoreError.NativeFailure and
      not disk.opened # No acquired writer exists to override the original native open refusal.
  let reopened = openLightPagedStore(disk, directory, initial.trust, selected).value
  check(reopened, 2)
  assert disk.retirementPending # The durable descriptor survives successful prior absence confirmation.
  assert disk.retire(disk.prepareLightRetirement.value).value.alreadyAbsent
  resetIo()
  assert disk.commit(prepareLightProofMerge(second, added).value).error == LightStoreError.StaleView
  noIo()
  let nextFacts = fixture.facts(1)
  let nextView = captureProofView(nextFacts, fixture.blocks[1].trust.identity.stateRoot,
      selected.head.view).value
  let advanced = prepareLightHeadAdvance(reopened, fixture.blocks[1].trust, nextView).value
  let third = disk.commit(advanced).value
  check(third, 2)
  assert third.head.len == 2
  assert sameApplicationCheckpoint(third.head.current.value.identity, fixture.blocks[
      1].trust.identity)
  assert uint64(third.manifest.sequence) == 1 and uint64(third.manifest.epoch) == 3
  assert array[32, byte](third.head.stateRoot) != array[32, byte](second.head.stateRoot)
  check(second, 2)
  assert disk.close == FileError.None
  let wrong = openLightPagedStore(disk, directory, initial.trust, selected)
  assert wrong.error != LightStoreError.None and not disk.opened
  let restored = openLightPagedStore(disk, directory, fixture.blocks[1].trust, fixture.blocks[
      1].limits).value
  check(restored, 2)
  assert restored.head.len == 2 and disk.retirementPending
  assert disk.retire(disk.prepareLightRetirement.value).error == LightStoreError.None
  assert disk.close == FileError.None
  check(restored, 2)
proc refusals(fixture: DiskHistoryFixture) =
  ## Default/policy/trust failures precede native mutation; exclusive initialization never silently opens an existing database.
  let source = fixture.blocks[0]
  let selected = source.limits
  var disk = default(LightPagedStore)
  assert disk.snapshot.error == LightStoreError.Uninitialized
  assert disk.commit(default(PreparedLightPublication)).error == LightStoreError.Uninitialized
  assert prepareLightProofMerge(default(LightStorageSnapshot), fixture.facts(0)).error ==
      LightStoreError.NotReady
  assert prepareLightHeadAdvance(default(LightStorageSnapshot), source.trust,
      source.empty.proofView).error == LightStoreError.NotReady
  var short = selected
  short.native.limits.contextBytes = ByteLimit(0)
  resetIo()
  assert initializeLightPagedStore(disk, path("v1-refused"), source.empty, short).error ==
      LightStoreError.PolicyMismatch
  short = selected
  short.native.root = fixture.blocks[1].trust.identity.stateRoot
  assert initializeLightPagedStore(disk, path("root-refused"), source.empty, short).error ==
      LightStoreError.TrustMismatch
  noIo()
  let directory = path("exclusive")
  let first = initializeLightPagedStore(disk, directory, source.empty, selected).value
  assert initializeLightPagedStore(disk, directory, source.empty, selected).error ==
      LightStoreError.Busy
  assert disk.commit(default(PreparedLightPublication)).error == LightStoreError.NotReady
  assert prepareLightProofMerge(first, default(VerifiedStateProofBatch)).error ==
      LightStoreError.HeadFailure
  assert prepareLightProofMerge(first, fixture.facts(1)).error == LightStoreError.HeadFailure
  assert prepareLightHeadAdvance(first, source.trust, source.empty.proofView).error ==
      LightStoreError.HeadFailure
  assert disk.close == FileError.None
  assert initializeLightPagedStore(disk, directory, source.empty, selected).error !=
      LightStoreError.None
  assert not disk.opened
  let restored = openLightPagedStore(disk, directory, source.trust, selected).value
  assert restored.manifest.bytes == first.manifest.bytes
  assert disk.close == FileError.None
proc publicationFaults(fixture: DiskHistoryFixture) =
  ## Every observed write/barrier/rename/close ordinal preserves a coherent old or new pair after fresh independent-root admission.
  let source = fixture.blocks[0]
  let selected = source.limits
  let added = fixture.facts(0)
  for operation in [writeIo, syncIo, renameIo, closeIo]:
    # A successful actual publication supplies reached call counts rather than guessed control positions.
    var disk = default(LightPagedStore)
    discard initializeLightPagedStore(disk, path("count-" & $operation), source.empty,
        selected).value
    let job = prepareLightProofMerge(disk.snapshot.value, added).value
    resetIo()
    assert disk.commit(job).error == LightStoreError.None
    let calls = ioCalls(operation)
    assert calls > 0
    assert disk.close == FileError.None
    for skip in 0..<int(calls):
      # Each failed trial owns a fresh namespace; unknown/candidate forensic files are never automatically removed.
      let directory = path("publish-fault-" & $operation & "-" & $skip)
      let before = initializeLightPagedStore(disk, directory, source.empty, selected).value
      let prepared = prepareLightProofMerge(before, added).value
      armIo(operation, cint(skip), 1, failedIo)
      assert disk.commit(prepared).error != LightStoreError.None
      assert pendingIo() == 0
      resetIo()
      assert disk.snapshot.error == LightStoreError.RecoveryRequired
      check(before, 0)
      discard disk.close
      let restored = openLightPagedStore(disk, directory, source.trust, selected).value
      let count = restored.head.proofView.len
      assert count == 0 or count == 2
      check(restored, count)
      assert uint64(restored.manifest.sequence) == uint64(if count == 0: 0 else: 1)
      assert disk.close == FileError.None
proc sameRootAdvance(fixture: DiskHistoryFixture) =
  ## Independent operator trust may select a successor posterior root equal to its parent; the native operation must then increment sequence.
  let source = fixture.blocks[0]
  let selected = source.limits
  let added = fixture.facts(0)
  let view = captureProofView(added, source.trust.identity.stateRoot, selected.head.view).value
  let original = captureLightHead(source.trust, view, selected.head).value
  let successor = rootTrust(fixture.blocks[1].trust, source.trust.identity.stateRoot)
  let directory = path("same-root-advance")
  var disk = default(LightPagedStore)
  let first = initializeLightPagedStore(disk, directory, original, selected).value
  let next = disk.commit(prepareLightHeadAdvance(first, successor, view).value).value
  check(next, 2)
  assert next.head.len == 2 and uint64(next.manifest.sequence) == 1
  assert array[32, byte](first.head.stateRoot) == array[32, byte](next.head.stateRoot)
  assert sameApplicationCheckpoint(next.head.current.value.identity, successor.identity)
  assert disk.close == FileError.None
  let restored = openLightPagedStore(disk, directory, successor, selected).value
  check(restored, 2)
  assert restored.head.len == 2 and disk.retirementPending
  assert disk.retire(disk.prepareLightRetirement.value).error == LightStoreError.None
  assert disk.close == FileError.None
proc startupFaults(fixture: DiskHistoryFixture) =
  ## Every observed startup read failure retires both owners; independent reopen admits the exact original metadata/proof pair.
  let source = fixture.blocks[0]
  let selected = source.limits
  let evidence = captureProofView(fixture.facts(0), source.trust.identity.stateRoot,
      selected.head.view).value
  let initial = captureLightHead(source.trust, evidence, selected.head).value
  let directory = path("startup-faults")
  var disk = default(LightPagedStore)
  let seeded = initializeLightPagedStore(disk, directory, initial, selected).value
  assert disk.close == FileError.None
  resetIo()
  check(openLightPagedStore(disk, directory, source.trust, selected).value, 2)
  let reads = ioCalls(readIo)
  assert reads > 0
  assert disk.close == FileError.None
  for skip in 0..<int(reads):
    # Repeated admission must never inherit a successful partial cache from a prior attempt.
    armIo(readIo, cint(skip), 1, failedIo)
    assert openLightPagedStore(disk, directory, source.trust, selected).error !=
        LightStoreError.None
    assert pendingIo() == 0 and not disk.opened
    resetIo()
    assert disk.snapshot.error == LightStoreError.Uninitialized
    let restored = openLightPagedStore(disk, directory, source.trust, selected).value
    assert restored.manifest.bytes == seeded.manifest.bytes
    check(restored, 2)
    assert disk.close == FileError.None
  for skip in 0..<2:
    # File and directory barrier failures invalidate the facade, even though retained snapshots stay independently readable.
    let retained = openLightPagedStore(disk, directory, source.trust, selected).value
    armIo(syncIo, cint(skip), 1, failedIo)
    assert disk.synchronize.error != LightStoreError.None and pendingIo() == 0
    resetIo()
    assert disk.snapshot.error == LightStoreError.RecoveryRequired
    check(retained, 2)
    discard disk.close
proc bounds(fixture: DiskHistoryFixture) =
  ## Retention, proof, context and workspace refusals precede native dispatch under independently tightened policy.
  let source = fixture.blocks[0]
  let selected = source.limits
  let view = captureProofView(fixture.facts(0), source.trust.identity.stateRoot,
      selected.head.view).value
  let initial = captureLightHead(source.trust, view, selected.head).value
  for channel in 0..<6:
    # Each actual resource channel is tightened separately; no failed bootstrap creates an artifact prefix.
    var short = selected
    case channel
    of 0: short.native.limits.dataset.entries = ElementLimit(1)
    of 1: short.proofs.proof.nodes = ElementLimit(0)
    of 2: short.proofs.batch.nodes = ElementLimit(0)
    of 3: short.contextBytes = ByteLimit(1)
    of 4: short.native.limits.workingBytes = ByteLimit(PagedStreamFixedBytes)
    else: short.head.view.items = ElementLimit(1) # Logical partial-view retention is separate from native query count.
    var disk = default(LightPagedStore)
    resetIo()
    assert initializeLightPagedStore(disk, path("bound-" & $channel), initial, short).error !=
        LightStoreError.None
    assert not disk.opened
    noIo()
proc emptyProducer(): PagedProducer =
  ## A valid empty knowledge set under an independently selected root does not mean a complete empty map.
  proc next(pass: int, ordinal: uint64, output: var storage_light_state_cache.LightStateProof): PagedProducerStep {.closure.} =
    ## Every pass consistently reports no stored queries.
    PagedProducerStep.End
  next
proc frame(inner: seq[byte], tag: byte): seq[byte] =
  ## Independent local-envelope oracle owns explicit E1/E8 widths rather than calling production framing.
  const magic = "RAGNAROK-LIGHT-PAGED-CONTEXT-V1\n"
  result = newSeq[byte](magic.len+9+inner.len)
  for index, character in magic: result[index] = byte(character) # Exact strict schema bytes.
  result[magic.len] = tag
  for index in 0..<8: result[magic.len+1+index] = byte((uint64(inner.len) shr (8*index)) and
      255) # Independent fixed-width little endian.
  for index in 0..<inner.len: result[magic.len+9+index] = inner[index] # Detached body transport.
proc malformedContext(fixture: DiskHistoryFixture) =
  ## Fully native-authenticated bytes still cannot grant a light application owner with wrong framing, trust or predecessor semantics.
  let source = fixture.blocks[0]
  let selected = source.limits
  let inner = encodeLightHead(source.empty, selected.contextBytes).value
  for kind in 0..<5:
    # Each genuine native artifact receives independently authored opaque context and no partial proof prefix.
    var context = frame(inner, 0)
    case kind
    of 0: context = inner # Raw header context is never an implicit application envelope.
    of 1: context = frame(inner, 2) # Unknown predecessor alternative.
    of 2: context.add(0) # E8 exact framing rejects trailing opaque bytes even with a valid native checksum.
    of 3: context = frame(encodeLightHead(fixture.blocks[1].empty, selected.contextBytes).value, 0)
    else: discard # The valid bootstrap envelope below is deliberately retained into an invalid successor epoch.
    let directory = path("context-" & $kind)
    var writer = default(PagedWriter)
    assert initializePagedWriter(writer, directory, selected.native, emptyProducer(), 0, 0,
        context).error == PagedNativeError.None
    if kind == 4:
      # A successor must include its exact predecessor; native byte integrity alone cannot reset application history.
      var candidate = default(PagedCandidate)
      assert preparePagedReplacement(writer, candidate, emptyProducer(), 0, 0, context).error ==
          PagedNativeError.None
      assert writer.publish(candidate).error == PagedNativeError.None
    assert writer.close == FileError.None
    var disk = default(LightPagedStore)
    let refused = openLightPagedStore(disk, directory, source.trust, selected)
    assert refused.error == LightStoreError.InvalidFormat or refused.error ==
        LightStoreError.HeadFailure
    assert not disk.opened
proc cycle(directory: string, source: BlockSnapshotResult, added: VerifiedStateProofBatch) =
  ## Fresh native ownership and every restored proof/context allocation retire within each activation.
  var disk = default(LightPagedStore)
  let retained = openLightPagedStore(disk, directory, source.trust, source.limits).value
  check(retained, 2)
  assert prepareLightProofMerge(retained, added).error == LightStoreError.None
  assert disk.close == FileError.None
  check(retained, 2)
proc main() {.raises.} =
  ## Independent complete fixtures only author evidence; the production light facade retains partial owners exclusively.
  let fixture = diskHistoryFixture(3, false)
  normal(fixture)
  refusals(fixture)
  publicationFaults(fixture)
  sameRootAdvance(fixture)
  startupFaults(fixture)
  bounds(fixture)
  malformedContext(fixture)
  let source = fixture.blocks[0]
  let added = fixture.facts(0)
  let directory = path("cycles")
  var disk = default(LightPagedStore)
  let first = initializeLightPagedStore(disk, directory, source.empty, source.limits).value
  assert disk.commit(prepareLightProofMerge(first, added).value).error == LightStoreError.None
  assert disk.retire(disk.prepareLightRetirement.value).error == LightStoreError.None
  assert disk.close == FileError.None
  cycle(directory, source, added)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(directory, source,
      added) # Fresh startup, partial proof restoration and detached jobs cannot leak across activations.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_light_paged_store", 1000, before, after)
  echo "light paged store PASS"
try:
  main()
except:
  quit(2) # Fixture IO and native failures cannot be accepted as a successful light ownership trial.
