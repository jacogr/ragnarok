# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_assurance_signing_arc_release"}

## Genuine admitted pending data, real TLS private ownership, all-local durable renewal and native Services/worker leases precede exact independent assurance signature checks.
import std/[assertions, syncio, dirs, paths, monotimes, times, strutils]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/app/proof/[worker, assurance_storage, assurance_acquisition, assurance_signing]
import ../../../src/jamnp-s/[work_signer, assurance_possession, assurance_duty, assurance_store,
  assurance_record, availability_proof]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[assurances, bounded, header]
import ../../../src/codec/state/[safrole, layout, trie]
import ../../../src/codec/work/report
import ../../../src/state/store
import ../../../src/state/availability/specifier
import ../../../src/crypto/primitives
import ../../../src/rpc/server
import ../../../src/lib/atomic/file
import ../../support/[jamnp_assurance_fixture, assurance_signer_context,
  current_application_context,
  pvm_computed_chain, storage_io, arc_evidence]
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset observed actual crypto attempts and explicitly selected maintained-provider failures.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Read counts only after synchronous execution or exact collection/join.
proc signatures(): cint {.importc: "ro_sign_calls", cdecl.}
  ## A real private Ed25519 attempt must occur only after every selected local coordinate is durably renewed.
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield under monotonic deadlines without touching leased native/source/key aliases.
proc limits(): AssurancePossessionLimits =
  ## Source, selected coordinates, complete logical IO/hash work and peak single-record workspace are explicit independent policies.
  AssurancePossessionLimits(duty: AssuranceDutyLimits(chapterBytes: ByteLimit(1000000),
    readBytes: ByteLimit(4000000), reports: ElementLimit(341), requests: ElementLimit(341*1023)),
    shards: ElementLimit(16), hashes: ElementLimit(100000), ioBytes: ByteLimit(64000000),
    hashBytes: ByteLimit(64000000), workspaceBytes: ByteLimit(64000000))
proc storage(): AssuranceStoreLimits =
  ## Four exact coordinates keep old promises resident while repeated-identity tests acquire the additional required shard.
  AssuranceStoreLimits(entries: ElementLimit(4), scanEntries: ElementLimit(400), bytes: ByteLimit(
      64000000),
    record: AssuranceRecordLimits(bytes: ByteLimit(16000000),
        verification: AvailabilityMerkleLimits(
      bytes: ByteLimit(64000000), hashes: ElementLimit(100000), hashBytes: ByteLimit(64000000))))
proc selection(): AssuranceBits =
  ## Literal core-zero LSB selection contains no caller-issued possession assertion.
  result = default(AssuranceBits)
  result.bytes[0] = 1
proc clean(folder: string) =
  ## Only test-owned paths are removed after all declared native/source/key borrowers retire.
  try: removeDir(path(folder))
  except: assert false, "signing fixture cleanup"
proc retain(owner: var AssuranceStore, fixture: AssuranceAcquisitionFixture,
    source: BlockSnapshotResult, ordinal: int, now: uint64) =
  ## Construct and independently verify actual original erasure data before its real file/directory publication.
  let duty = captureAssuranceDuty(source, fixture.local, limits().duty).value
  let request = duty.shardRequest(CoreIndex(0), ordinal).value
  let specifier = fixture.availability.availabilityInfo.value.specifier
  let prepared = prepareAvailabilityTransfer(fixture.availability, request, storage().record.verification).value
  let verified = verifyAvailabilityTransfer(specifier, request, prepared.bundleShard,
    prepared.segmentShards, prepared.justification, storage().record.verification)
  assert verified.error == AvailabilityTransferError.None, "genuine original assigned shard proof"
  assert owner.rememberAssuranceShard(verified.value, AssuranceTime(now)).error ==
      AssuranceStoreError.None, "actual durable shard publication"
proc repeated(source: BlockSnapshotResult, local: StateEdKey): BlockSnapshotResult =
  ## This explicitly independently trusted structural roster variant isolates repeated-key/source-root handling; the ordinary source remains genuinely computed/admitted/published.
  let saved = source.value
  let key = chapterKey(StateChapter(8))
  let policy = ValidatorStateConfig(cores: saved.cores, validators: ElementLimit(1023),
      maxBytes: ByteLimit(1000000))
  let decoded = decodeStateValidators(saved.lookup(key).value.bytes, policy).value.value
  var roster = newSeq[StateValidator](9)
  for index in 0..<9: roster[index] = validatorAt(decoded, StateValidatorIndex(index)).value
  roster[2].ed25519 = local
  let chapter = validatorEntry(ValidatorChapter.Active, roster, policy).value
  var entries: seq[StateEntry] = @[]
  for index in 0..<saved.keyCount:
    # Recommit the whole complete map while preserving the exact sealed header to witness full posterior-root revocation.
    let selected = saved.keyAt(StateKeyIndex(index))
    if array[31, byte](selected) != array[31, byte](key): entries.add(StateEntry(key: selected,
        value: saved.lookup(selected).value.bytes))
  entries.add(chapter)
  captureBlockSnapshot(chainHeaderBytes(saved.header), entries, saved.chainParameters)
proc verifyWire(signed: SignedAssurance, source: BlockSnapshotResult, local: StateEdKey) =
  ## Independent literal transcript assembly never calls the production assurance-message constructor or codec verifier.
  let encoded = signed.assuranceBytes(source, ByteLimit(97))
  assert encoded.error == AssuranceSigningError.None and encoded.value.len == 97, "CE141 exact anchor+one-byte-bits+64-byte-signature without ordinal"
  let wire = encoded.value
  let anchor = array[32, byte](source.value.blockHash)
  var preimage = default(array[33, byte])
  for index in 0..<32:
    assert wire[index] == anchor[index], "exact parent anchor"
    preimage[index] = anchor[index]
  assert wire[32] == 1, "fixed LSB-first three-core bitfield"
  preimage[32] = 1
  let digest = array[32, byte](blake2b256(preimage).value)
  var message = default(array[45, byte])
  const token = [106'u8, 97, 109, 95, 97, 118, 97, 105, 108, 97, 98, 108, 101]
  for index in 0..<13: message[index] = token[index] # Exact ASCII jam_available, no dollar/count/ordinal/terminator.
  for index in 0..<32: message[13+index] = digest[index]
  var signature = default(array[64, byte])
  for index in 0..<64: signature[index] = wire[33+index]
  assert verify(EdPublicKey(array[32, byte](local)), EdSignature(signature), message), "actual Ed25519 signature over independent fixed transcript"
  assert signed.assuranceBytes(source, ByteLimit(96)).error == AssuranceSigningError.LimitExceeded, "whole output deficit has no prefix"
proc direct(owner: var AssuranceStore, fixture: AssuranceAcquisitionFixture, signer: WorkSigner,
    folder: string) =
  ## Actual storage, whole preflight and all original local coordinates must precede every private signature attempt.
  reset(0)
  let missing = signer.signStoredAssurance(owner, fixture.source, fixture.chain, selection(),
      AssuranceTime(1000), limits())
  assert missing.error == AssuranceSigningError.PossessionFailure, "missing assigned data has no signature"
  assert missing.possessionError.error == AssurancePossessionError.NoPossession and signatures() ==
      0, "no private key use before possession"
  var invalid = selection()
  invalid.bytes[0] = 8
  reset(0)
  let padding = signer.signStoredAssurance(owner, fixture.source, fixture.chain, invalid,
      AssuranceTime(1000), limits())
  assert padding.error == AssuranceSigningError.PossessionFailure and
      padding.possessionError.error == AssurancePossessionError.InvalidSelection, "nonexistent high core bit cannot disappear from a signature"
  assert signatures() == 0 and hashes() == 0, "invalid fixed-bitfield selection precedes all crypto"
  retain(owner, fixture, fixture.source, 0, 1000)
  let duty = captureAssuranceDuty(fixture.source, fixture.local, limits().duty).value
  let request = duty.shardRequest(CoreIndex(0), 0).value
  let plan = availabilityVerificationInfo(fixture.availability.availabilityInfo.value.specifier, request).value
  var exact = limits()
  exact.shards = ElementLimit(1)
  exact.hashes = ElementLimit(plan.hashes+3)
  exact.hashBytes = ByteLimit(plan.hashBytes+348+33)
  exact.ioBytes = ByteLimit((plan.payloadBytes+uint64(AssuranceRecordHeaderBytes))*2+1)
  exact.workspaceBytes = ByteLimit(plan.payloadBytes*3+uint64(AssuranceRecordHeaderBytes))
  for kind in 0..<4:
    # Every whole-operation deficit refuses before the first record hash, IO barrier or Ed25519 attempt.
    var narrow = exact
    case kind
    of 0: narrow.hashes = ElementLimit(uint64(exact.hashes)-1)
    of 1: narrow.hashBytes = ByteLimit(uint64(exact.hashBytes)-1)
    of 2: narrow.ioBytes = ByteLimit(uint64(exact.ioBytes)-1)
    else: narrow.workspaceBytes = ByteLimit(uint64(exact.workspaceBytes)-1)
    reset(0)
    resetIo()
    let failed = signer.signStoredAssurance(owner, fixture.source, fixture.chain, selection(),
        AssuranceTime(1001), narrow)
    assert failed.error == AssuranceSigningError.PossessionFailure, "aggregate deficit is not a signed prefix"
    assert failed.possessionError.error == AssurancePossessionError.LimitExceeded, "actual whole-plan refusal"
    assert hashes() == 0 and signatures() == 0 and ioCalls(syncIo) == 0, "preflight before hashing, persistence or private signature"
  reset(0)
  let accepted = signer.signStoredAssurance(owner, fixture.source, fixture.chain, selection(),
      AssuranceTime(1001), exact)
  assert accepted.error == AssuranceSigningError.None and signatures() == 1, "exact budgets permit one signature after renewal"
  assert uint64(hashes()) == plan.hashes+3, "one complete record restore, renewed metadata and exact final transcript hash"
  verifyWire(accepted.value, fixture.source, fixture.local)
  let changed = repeated(fixture.source, fixture.local)
  assert changed.error == GenesisError.None, "complete repeated-key structural source"
  assert array[32, byte](changed.value.blockHash) == array[32, byte](
      fixture.source.value.blockHash), "identical sealed header control"
  assert accepted.value.assuranceBytes(changed, ByteLimit(97)).error ==
      AssuranceSigningError.StaleSource, "equal anchor with changed complete posterior root revokes publication"
  reset(0)
  let partial = signer.signStoredAssurance(owner, changed, fixture.chain, selection(),
      AssuranceTime(1002), limits())
  assert partial.error == AssuranceSigningError.PossessionFailure and
      partial.possessionError.error == AssurancePossessionError.NoPossession, "one missing repeated-key coordinate clears the whole core"
  assert signatures() == 0, "same TLS key cannot sign possession for only one original position"
  retain(owner, fixture, changed, 1, 1002)
  reset(0)
  let all = signer.signStoredAssurance(owner, changed, fixture.chain, selection(), AssuranceTime(
      1003), limits())
  assert all.error == AssuranceSigningError.None and signatures() == 1, "all original local coordinates permit one valid identity signature"
  assert all.value.assuranceInfo.value.shards == 2, "both original positions independently reverified and durably renewed"
  verifyWire(all.value, changed, fixture.local)
  var root = ""
  for octet in request.root.bytes: root.add(toHex(int(octet), 2).toLowerAscii())
  let file = folder & "/" & root.substr(0, 1) & "/" & root & "-" & toHex(int(uint64(request.shard)),
      4).toLowerAscii() & ".shard"
  let original = readBoundedFile(file, storage().record.bytes).value
  var oversized = original
  for index in 0..<4096: oversized.add(0) # Test-owned trailing data exceeds the canonical expected record extent without changing its fixed header.
  assert replaceAtomicFile(file, oversized, ByteLimit(uint64(oversized.len))) ==
      AtomicFileError.None, "oversized archive fixture"
  reset(0)
  resetIo()
  limitReads(1)
  let bounded = signer.signStoredAssurance(owner, fixture.source, fixture.chain, selection(),
      AssuranceTime(1004), limits())
  let readCalls = ioCalls(readIo)
  let signCalls = signatures()
  resetIo()
  assert replaceAtomicFile(file, original, storage().record.bytes) == AtomicFileError.None, "restore exact test-owned promise"
  assert owner.close().error == AssuranceStoreError.None, "retire observed bad-file owner"
  assert owner.openAssuranceStore(folder, fixture.chain, storage()).error ==
      AssuranceStoreError.None, "recover exact original namespace before reporting read-bound result"
  assert bounded.error == AssuranceSigningError.PossessionFailure and signCalls == 0, "oversized record grants no signature"
  assert readCalls == 0, "canonical expected extent refuses oversized archive before any payload read"
  var foreign = original
  foreign[40] = foreign[40] xor 1 # Change only the package identity while keeping exact geometry, root, payload and extent.
  let checksum = array[32, byte](blake2b256(foreign.toOpenArray(0, 173)).value)
  for index in 0..<32: foreign[174+index] = checksum[index]
  assert replaceAtomicFile(file, foreign, storage().record.bytes) == AtomicFileError.None, "checksum-correct foreign metadata fixture"
  reset(0)
  let conflict = signer.signStoredAssurance(owner, fixture.source, fixture.chain, selection(),
      AssuranceTime(1004), limits())
  let contextHashes = hashes()
  let contextSigns = signatures()
  assert replaceAtomicFile(file, original, storage().record.bytes) == AtomicFileError.None, "preserve original context after bounded refusal"
  assert conflict.error == AssuranceSigningError.PossessionFailure and
      conflict.possessionError.error == AssurancePossessionError.NoPossession, "foreign complete metadata cannot support canonical possession"
  assert contextHashes == 1 and contextSigns == 0 and not owner.faulted, "context mismatch stops after metadata checksum before any payload proof"
  for barrier in 0..1:
    # Data-sync refusal preserves the old usable prefix; directory-sync refusal faults the namespace and never signs uncertain retention.
    reset(0)
    resetIo()
    armIo(syncIo, cint(barrier), 1, failedIo)
    let failed = signer.signStoredAssurance(owner, fixture.source, fixture.chain, selection(),
        AssuranceTime(1004), limits())
    assert failed.error == AssuranceSigningError.PossessionFailure and pendingIo() == 0, "actual renewal barrier refusal"
    let failure = failed.possessionError.error
    let attempts = signatures()
    assert failure == AssurancePossessionError.StorageFailure, "actual durable-renewal child refusal"
    assert attempts == 0, "no private signature before complete actual durability"
    if barrier == 0: assert not owner.faulted, "prepublication refusal preserves healthy original promise"
    else: assert owner.faulted, "visible uncertain renewal closes the signing gate"
  resetIo()
  reset(0)
proc staged(owner: var AssuranceStore, fixture: AssuranceAcquisitionFixture, signer: WorkSigner,
    now: uint64): AssuranceSigningJob =
  ## Retire temporary source/key/result aliases before moving this closed job into native execution.
  let admitted = captureAssuranceSigning(owner, fixture.source, signer, fixture.chain,
    selection(), AssuranceTime(now), limits())
  assert admitted.error == AssuranceSigningJobError.None, "complete bounded signing capture"
  admitted.value
proc waitDone(worker: var StateProofWorker) =
  ## Only synchronized scalar phase is observed while private key/source/native aliases belong to the worker.
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while worker.phase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "bounded signing completion"
    discard pauseMicros(100)
proc waitDone(owner: var Services) =
  ## Cached host status and unrelated ticks remain safe under the exact canonical/private-key/archive lease.
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "bounded managed signing completion"
    owner.tick(0)
    discard pauseMicros(100)
proc cycle(worker: var StateProofWorker, owner: var AssuranceStore,
    fixture: AssuranceAcquisitionFixture, signer: WorkSigner, index: int) =
  ## Completed cancellation hides the real signature while preserving every already renewed record until exact collection.
  var job = staged(owner, fixture, signer, uint64(2000+index))
  let admitted = worker.submit(job)
  assert admitted.error == ProofWorkerError.None and not job.valid, "moved private signing job"
  worker.waitDone()
  assert worker.collect(default(ProofWorkerTicket)).kind == ProofWorkerCompletionKind.Uninitialized, "foreign ticket cannot release private key/namespace borrow"
  if index mod 2 == 0: assert worker.cancel(admitted.value), "exact completed signing cancellation"
  let completed = worker.collect(admitted.value)
  if index mod 2 == 0:
    assert completed.kind == ProofWorkerCompletionKind.Cancelled, "cancelled result exposes no signature"
  else:
    assert completed.kind == ProofWorkerCompletionKind.AssuranceSigned, "exact native signed completion"
    assert completed.assuranceSigningValue.error == AssuranceSigningError.None, "actual native durable possession and signature"
  assert not owner.faulted, "namespace observed only after exact retirement"
proc managed(fixture: AssuranceAcquisitionFixture, keyPath, certificatePath,
    suffix: string) {.raises.} =
  ## The genuinely executed complete child is an explicit trusted seed here; this component test does not claim network bootstrap or adoption from another genesis.
  var chainFile = "assurance-signing-chain-" & suffix & ".json"
  let folder = "assurance-signing-managed-" & suffix
  writeFile(chainFile, currentApplicationText(fixture.source.value))
  clean(folder)
  defer:
    discard posix.unlink(chainFile.toCString())
    clean(folder)
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--chain", chainFile, "--with-state",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(options, "stored assurance signing"), "actual complete Services"
  assert not owner.assuranceSigningConfigured, "private signing disabled by default"
  assert owner.configureAssuranceSigner(certificatePath, keyPath, fixture.local).error ==
      WorkSigningSetupError.InvalidStorage, "no implicit archive activation"
  let opened = owner.beginAssuranceStorage(folder, storage(), AssuranceStorageMode.Create).value
  owner.waitDone()
  assert owner.collectStateProof(opened).assuranceStorageValue.error == AssuranceStoreError.None, "actual namespace setup"
  assert owner.configureAssuranceSigner(certificatePath, keyPath, fixture.local).error ==
      WorkSigningSetupError.None, "private signer bound to actual TLS identity"
  let source = fixture.availability.availabilityInfo.value.specifier
  let request = captureAssuranceDuty(fixture.source, fixture.local, limits(
    ).duty).value.shardRequest(CoreIndex(0), 0).value
  let transfer = prepareAvailabilityTransfer(fixture.availability, request, storage().record.verification).value
  var wire: seq[byte] = @[]
  for message in [transfer.bundleShard, transfer.segmentShards, transfer.justification]:
    # Independent three-E4 input framing reaches ordinary managed acquisition, never direct mutation of Services' private archive.
    for index in 0..<4: wire.add(byte((uint32(message.len) shr (8*index)) and 255))
    for octet in message: wire.add(octet)
  let acquisition = AssuranceAcquisitionLimits(duty: limits().duty, verification: storage(
    ).record.verification,
    wireBytes: ByteLimit(16000000), workspaceBytes: ByteLimit(128000000))
  let acquired = owner.beginAssuranceAcquisition(fixture.local, CoreIndex(0), 0, wire,
      AssuranceTime(1000), acquisition).value
  owner.waitDone()
  assert owner.collectStateProof(acquired).assuranceAcquisitionValue.error ==
      AssuranceAcquisitionError.None, "actual managed acquired shard"
  let admitted = owner.beginAssuranceSigning(selection(), AssuranceTime(1001), limits()).value
  assert owner.stateProofActive and owner.rpc.chainPaused, "signer/source/archive lease remains exclusive"
  owner.waitDone()
  let completed = owner.collectStateProof(admitted)
  assert completed.kind == ProofWorkerCompletionKind.AssuranceSigned and
      completed.assuranceSigningValue.error == AssuranceSigningError.None, "actual managed stored-possession signature"
  let signed = completed.assuranceSigningValue.value
  assert owner.currentAssuranceBytes(signed, ByteLimit(97)).error == AssuranceSigningError.None, "only this Services instance's collected signature may publish"
  let cancelled = owner.beginAssuranceSigning(selection(), AssuranceTime(1002), limits()).value
  owner.waitDone()
  assert owner.cancelStateProof(cancelled), "completed signature cancellation"
  assert owner.collectStateProof(cancelled).kind == ProofWorkerCompletionKind.Cancelled, "cancelled private result withheld"
  assert owner.currentAssuranceBytes(signed, ByteLimit(97)).error ==
      AssuranceSigningError.StaleSource, "previous signature cannot bypass cancelled turn"
  owner.close()
  assert owner.currentAssuranceBytes(signed, ByteLimit(97)).error ==
      AssuranceSigningError.StaleSource, "closed lifetime revokes publication"
  assert owner.start(options, "assurance signing restart"), "same complete source can restart"
  let reopened = owner.beginAssuranceStorage(folder, storage(), AssuranceStorageMode.Open).value
  owner.waitDone()
  assert owner.collectStateProof(reopened).assuranceStorageValue.error == AssuranceStoreError.None, "actual retained restart"
  assert owner.configureAssuranceSigner(certificatePath, keyPath, fixture.local).error ==
      WorkSigningSetupError.None, "new private signer lifetime"
  assert owner.currentAssuranceBytes(signed, ByteLimit(97)).error ==
      AssuranceSigningError.StaleSource, "identical root/key/namespace cannot revive an older Services signature"
  let fresh = owner.beginAssuranceSigning(selection(), AssuranceTime(1003), limits()).value
  owner.waitDone()
  let current = owner.collectStateProof(fresh).assuranceSigningValue
  assert current.error == AssuranceSigningError.None, "new lifetime performs fresh stored verification and private signature"
  assert owner.currentAssuranceBytes(current.value, ByteLimit(97)).error ==
      AssuranceSigningError.None, "newly collected signature publishes"
  assert owner.currentAssuranceBytes(signed, ByteLimit(97)).error ==
      AssuranceSigningError.StaleSource, "new valid signature does not revive an old same-root/key result"
  assert current.value.assuranceBytes(fixture.source, ByteLimit(97)).value == signed.assuranceBytes(
      fixture.source, ByteLimit(97)).value, "identical deterministic wire bytes do not substitute for current Services authorization"
proc main() {.raises.} =
  ## Genuine report/chain publication precedes private TLS fixture loading and any assertion of stored availability.
  reset(0)
  resetIo()
  let fixture = assuranceAcquisitionFixture()
  let suffix = $storageProcessId()
  var keyPath = "assurance-signing-key-" & suffix & ".pem"
  var certificatePath = "assurance-signing-cert-" & suffix & ".pem"
  assuranceSignerFiles(keyPath, certificatePath)
  defer:
    discard posix.unlink(keyPath.toCString())
    discard posix.unlink(certificatePath.toCString())
  let loaded = loadWorkSigner(certificatePath, keyPath)
  assert loaded.error == WorkSignerError.None, "real TLS-matched private signer"
  let signer = loaded.value
  assert array[32, byte](signer.signerIdentity.value) == array[32, byte](fixture.local), "actual original computed-roster key matches TLS seed"
  let folder = "assurance-signing-" & suffix
  clean(folder)
  defer: clean(folder)
  var owner = default(AssuranceStore)
  defer: discard owner.close()
  assert owner.createAssuranceStore(folder, fixture.chain, storage()).error ==
      AssuranceStoreError.None, "explicit native archive"
  direct(owner, fixture, signer, folder)
  assert owner.close().error == AssuranceStoreError.None, "close after witnessed uncertain renewal"
  assert owner.openAssuranceStore(folder, fixture.chain, storage()).error ==
      AssuranceStoreError.None, "verified restart restores real retained data"
  reset(8)
  let refused = signer.signStoredAssurance(owner, fixture.source, fixture.chain, selection(),
      AssuranceTime(1005), limits())
  assert refused.error == AssuranceSigningError.CryptoFailure and signatures() == 1, "real signing backend refusal has no successful signature"
  reset(0)
  managed(fixture, keyPath, certificatePath, suffix)
  var worker = default(StateProofWorker)
  defer: worker.close() # Join private key/source/archive borrowers before any outer alias retires.
  assert worker.start(), "bounded reusable signing worker"
  cycle(worker, owner, fixture, signer, 1)
  let before = getOccupiedMem()
  for index in 0..<1000:
    # Complete native proof restoration, durable renewal, actual signature and both collection alternatives retire in isolated activations.
    cycle(worker, owner, fixture, signer, index+1)
  let after = getOccupiedMem()
  assert before == after, "stored assurance signing ARC release"
  recordArcRelease("jamnp_assurance_signing", 1000, before, after)
  echo "JAMNP-S assurance signing passed"
try:
  main()
except:
  quit(2)
