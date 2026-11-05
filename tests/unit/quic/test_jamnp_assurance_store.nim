# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_assurance_store_arc_release"}

## Real private directories, synchronized records and observed OS failures exercise durable assurance storage without fabricating canonical duty or signing authority.
import std/[assertions, syncio, dirs, paths, strutils]
import std/posix/posix
import ../../../src/jamnp-s/[assurance_store, assurance_record, availability_proof]
import ../../../src/lib/atomic/file as atomic_file
import ../../../src/codec/bounded
import ../../../src/state/availability/specifier
import ../../../src/state/erasure/words
import ../../support/[pvm_computed_report, storage_io, storage_crash, arc_evidence]
proc limits(): AssuranceStoreLimits =
  ## Explicit storage can scale on disk while resident metadata and every record's working set remain independent of archive size.
  AssuranceStoreLimits(entries: ElementLimit(4), scanEntries: ElementLimit(1000),
    bytes: ByteLimit(64000000), record: AssuranceRecordLimits(bytes: ByteLimit(16000000),
      verification: AvailabilityMerkleLimits(bytes: ByteLimit(64000000), hashes: ElementLimit(
          10000), hashBytes: ByteLimit(64000000))))
proc chain(): AssuranceChainId =
  ## Independently selected chain identity cannot come from a stored record or incoming shard.
  var bytes = default(array[32, byte])
  bytes[0] = 37
  AssuranceChainId(bytes)
proc name(suffix: string): string =
  ## Every test owns a process-specific dedicated namespace under the runner's ignored working directory.
  "assurance-store-" & $storageProcessId() & "-" & suffix
proc clean(folder: string) =
  ## Only test-generated private paths are recursively removed, after explicit owner retirement.
  try: removeDir(path(folder))
  except: assert false, "test namespace cleanup"
proc shard(source: AvailabilityCommitment, index: uint64): VerifiedAvailabilityTransfer =
  ## Genuine original computation/erasure and actual proof verification supply the complete detached distribution.
  let spec = source.availabilityInfo.value.specifier
  let request = AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
    root: spec.erasureRoot, shard: ErasureShardIndex(index))
  let prepared = prepareAvailabilityTransfer(source, request, limits().record.verification).value
  let verified = verifyAvailabilityTransfer(spec, request, prepared.bundleShard,
    prepared.segmentShards, prepared.justification, limits().record.verification)
  assert verified.error == AvailabilityTransferError.None, "genuine source proof"
  verified.value
proc location(folder: string, transfer: VerifiedAvailabilityTransfer): string =
  ## Independent fixture naming follows the documented full-root/E2 coordinate spelling, not a production path getter.
  var text = ""
  for octet in transfer.specifier.erasureRoot.bytes: text.add(toHex(int(octet), 2).toLowerAscii())
  folder & "/" & text.substr(0, 1) & "/" & text & "-" & toHex(int(uint64(transfer.request.shard)),
      4).toLowerAscii() & ".shard"
proc ordinary(first, second, third: VerifiedAvailabilityTransfer) =
  ## Successful publication, duplicate extension and actual close/reopen preserve all promises, exact bytes and fixed scalar accounting.
  let folder = name("ordinary")
  clean(folder)
  defer: clean(folder)
  var owner = default(AssuranceStore)
  defer: discard owner.close()
  assert not owner.opened and not owner.faulted, "default disabled"
  assert not default(StoredAssuranceShard).valid, "default has no stored-data receipt"
  assert owner.loadAssuranceShard(first.specifier, first.request).error ==
      AssuranceStoreError.Closed, "closed lookup"
  var policy = limits()
  policy.entries = ElementLimit(2)
  assert owner.createAssuranceStore(folder, chain(), policy).error == AssuranceStoreError.None, "create dedicated chain namespace"
  assert owner.opened and owner.len == 0 and owner.byteLength == 0, "empty durable namespace"
  var competitor = default(AssuranceStore)
  defer: discard competitor.close()
  let busy = competitor.openAssuranceStore(folder, chain(), policy)
  assert busy.error == AssuranceStoreError.FileFailure and busy.fileError == AtomicFileError.Busy, "single writer excludes independent owner"
  let stored = owner.rememberAssuranceShard(first, AssuranceTime(1000))
  assert stored.error == AssuranceStoreError.None and stored.value.valid, "successful sync grants receipt"
  let original = stored.value.storedInfo.value
  assert uint64(original.retainUntil) == 1000'u64+2419200, "real 28-day promise"
  assert owner.len == 1 and owner.byteLength == original.encodedBytes, "exact serialized accounting"
  assert owner.rememberAssuranceShard(first, AssuranceTime(999)).error ==
      AssuranceStoreError.InvalidTime, "time cannot regress"
  let renewed = owner.rememberAssuranceShard(first, AssuranceTime(1100))
  assert renewed.error == AssuranceStoreError.None, "duplicate extends durable promise"
  assert uint64(renewed.value.storedInfo.value.retainUntil) >= uint64(original.retainUntil), "old horizon preserved"
  assert uint64(stored.value.storedInfo.value.promisedAt) == 1000, "old detached receipt remains immutable"
  assert owner.rememberAssuranceShard(second, AssuranceTime(1200)).error ==
      AssuranceStoreError.None, "second distinct shard"
  let occupied = owner.byteLength
  assert owner.rememberAssuranceShard(third, AssuranceTime(1200)).error ==
      AssuranceStoreError.LimitExceeded, "no eviction at full capacity"
  assert owner.len == 2 and owner.byteLength == occupied, "capacity refusal preserves all promises"
  assert owner.close().error == AssuranceStoreError.None and not owner.opened, "explicit joined owner retirement"
  assert owner.openAssuranceStore(folder, chain(), policy).error == AssuranceStoreError.None, "restart scalar accounting"
  assert owner.len == 2 and owner.byteLength == occupied, "restart count and byte preservation"
  let restored = owner.loadAssuranceShard(first.specifier, first.request)
  assert restored.error == AssuranceStoreError.None, "restart full proof and sync"
  let copied = restored.value.storedTransfer(ByteLimit(16000000)).value
  assert copied.bundleShard == first.bundleShard and copied.segmentShards == first.segmentShards and
      copied.justification == first.justification, "exact restored CE137 payloads"
  assert owner.rememberAssuranceShard(first, AssuranceTime(1099)).error ==
      AssuranceStoreError.InvalidTime, "restart preserves maximum promise clock"
  let exact = prepareAssuranceRecord(first, chain(), AssuranceTime(1000),
      policy.record).value.recordInfo.value.encodedBytes
  assert owner.close().error == AssuranceStoreError.None, "close before independent namespaces"
  var wrongChain = array[32, byte](chain())
  wrongChain[0] = wrongChain[0] xor 1
  assert owner.openAssuranceStore(folder, AssuranceChainId(wrongChain), policy).error ==
      AssuranceStoreError.InvalidNamespace, "wrong chain never adopted"
  assert not owner.opened, "failed open retains no lock or admission"
  assert owner.createAssuranceStore(folder, chain(), policy).error ==
      AssuranceStoreError.AlreadyExists, "creation cannot overwrite history"
  let tinyFolder = name("capacity")
  clean(tinyFolder)
  defer: clean(tinyFolder)
  policy = limits()
  policy.bytes = ByteLimit(exact-1)
  assert owner.createAssuranceStore(tinyFolder, chain(), policy).error == AssuranceStoreError.None, "explicit small disk ceiling"
  assert owner.rememberAssuranceShard(first, AssuranceTime(1000)).error ==
      AssuranceStoreError.LimitExceeded, "whole record precharged before write"
  assert owner.len == 0 and owner.byteLength == 0, "no capacity prefix"
  assert owner.loadAssuranceShard(first.specifier, first.request).error ==
      AssuranceStoreError.Missing, "refused record was never published"
  assert owner.close().error == AssuranceStoreError.None, "retire small-capacity namespace before cleanup"
proc conflicts(first: VerifiedAvailabilityTransfer) =
  ## An independently verified same-root/different-package descriptor cannot overwrite an earlier canonical-context promise.
  let folder = name("conflict")
  clean(folder)
  defer: clean(folder)
  var owner = default(AssuranceStore)
  defer: discard owner.close()
  assert owner.createAssuranceStore(folder, chain(), limits()).error == AssuranceStoreError.None, "conflict namespace"
  assert owner.rememberAssuranceShard(first, AssuranceTime(1000)).error == AssuranceStoreError.None, "original promise"
  let bytes = owner.byteLength
  var alternate = first.specifier
  alternate.packageHash.bytes[0] = alternate.packageHash.bytes[0] xor 1
  let verified = verifyAvailabilityTransfer(alternate, first.request, first.bundleShard,
    first.segmentShards, first.justification, limits().record.verification)
  assert verified.error == AvailabilityTransferError.None, "Merkle proof alone does not authenticate package metadata"
  assert owner.rememberAssuranceShard(verified.value, AssuranceTime(1100)).error ==
      AssuranceStoreError.Conflict, "all six canonical fields remain bound"
  assert owner.byteLength == bytes and owner.len == 1, "conflict preserved original"
  assert uint64(owner.loadAssuranceShard(first.specifier,
      first.request).value.storedInfo.value.promisedAt) == 1000, "conflict cannot advance promise clock"
proc failures(first, second: VerifiedAvailabilityTransfer) =
  ## Real prepublication and visible-but-unsynced OS failures cannot manufacture successful receipts or damage older committed files.
  let folder = name("faults")
  clean(folder)
  defer: clean(folder)
  var owner = default(AssuranceStore)
  defer: discard owner.close()
  assert owner.createAssuranceStore(folder, chain(), limits()).error == AssuranceStoreError.None, "fault namespace"
  assert owner.rememberAssuranceShard(first, AssuranceTime(1000)).error == AssuranceStoreError.None, "old committed record"
  let oldBytes = owner.byteLength
  resetIo()
  armIo(syncIo, 0, 1, failedIo)
  let refused = owner.rememberAssuranceShard(second, AssuranceTime(1100))
  assert refused.error == AssuranceStoreError.FileFailure and refused.fileError ==
      AtomicFileError.IoFailure, "data file sync refusal before publication"
  assert pendingIo() == 0, "actual injected data barrier consumed"
  resetIo()
  assert not owner.faulted and owner.len == 1 and owner.byteLength == oldBytes, "ordinary refusal preserves healthy old prefix"
  assert owner.loadAssuranceShard(first.specifier, first.request).error == AssuranceStoreError.None, "old promise still usable"
  assert owner.loadAssuranceShard(second.specifier, second.request).error ==
      AssuranceStoreError.Missing, "refused prefix not visible"
  resetIo()
  armIo(syncIo, 1, 1, failedIo)
  let uncertain = owner.rememberAssuranceShard(second, AssuranceTime(1100))
  assert uncertain.error == AssuranceStoreError.FileFailure and uncertain.fileError ==
      AtomicFileError.PublishedUnsynced, "directory sync uncertainty remains explicit"
  assert pendingIo() == 0 and owner.faulted, "uncertainty disables new receipts"
  resetIo()
  assert owner.loadAssuranceShard(first.specifier, first.request).error ==
      AssuranceStoreError.Faulted, "even valid old data cannot bypass faulted admission"
  assert owner.rememberAssuranceShard(first, AssuranceTime(1200)).error ==
      AssuranceStoreError.Faulted, "publication stops until recovery"
  assert owner.close().error == AssuranceStoreError.None, "retire uncertain owner"
  assert owner.openAssuranceStore(folder, chain(), limits()).error == AssuranceStoreError.None, "reopen counts actually visible records"
  assert owner.len == 2 and not owner.faulted, "recovered visible record count"
  resetIo()
  armIo(syncIo, 0, 1, failedIo)
  let failedRestore = owner.loadAssuranceShard(second.specifier, second.request)
  assert failedRestore.error == AssuranceStoreError.FileFailure and owner.faulted, "restore requires real synchronization before receipt"
  assert pendingIo() == 0, "actual restore barrier consumed"
  resetIo()
  assert owner.close().error == AssuranceStoreError.None, "close failed restore"
  assert owner.openAssuranceStore(folder, chain(), limits()).error == AssuranceStoreError.None, "second recovery"
  assert owner.loadAssuranceShard(second.specifier, second.request).error ==
      AssuranceStoreError.None, "full verified synced receipt after recovery"
proc restartDamage(first: VerifiedAvailabilityTransfer) =
  ## Header accounting is deliberately weaker than possession: corrupted payloads can never return stored-data success after restart.
  let folder = name("damage")
  clean(folder)
  defer: clean(folder)
  var owner = default(AssuranceStore)
  defer: discard owner.close()
  assert owner.createAssuranceStore(folder, chain(), limits()).error == AssuranceStoreError.None, "damage namespace"
  assert owner.rememberAssuranceShard(first, AssuranceTime(1000)).error == AssuranceStoreError.None, "original damage fixture"
  assert owner.close().error == AssuranceStoreError.None, "close before external corruption"
  let file = location(folder, first)
  let original = readBoundedFile(file, limits().record.bytes).value
  var damaged = original
  damaged[AssuranceRecordHeaderBytes] = damaged[AssuranceRecordHeaderBytes] xor 1
  assert replaceAtomicFile(file, damaged, limits().record.bytes) == AtomicFileError.None, "actual payload corruption"
  assert owner.openAssuranceStore(folder, chain(), limits()).error == AssuranceStoreError.None, "fixed header remains accountable"
  assert owner.loadAssuranceShard(first.specifier, first.request).error ==
      AssuranceStoreError.RecordFailure, "all payload proofs reverified before receipt"
  assert owner.faulted, "failed recovery requires explicit retirement"
  assert owner.close().error == AssuranceStoreError.None, "close damaged owner"
  assert replaceAtomicFile(file, original, limits().record.bytes) == AtomicFileError.None, "restore exact fixture"
  damaged = original
  damaged[174] = damaged[174] xor 1
  assert replaceAtomicFile(file, damaged, limits().record.bytes) == AtomicFileError.None, "actual header corruption"
  let broken = owner.openAssuranceStore(folder, chain(), limits())
  assert broken.error == AssuranceStoreError.HeaderFailure and not owner.opened, "startup refuses corrupt metadata"
  assert replaceAtomicFile(file, original, limits().record.bytes) == AtomicFileError.None, "repair header"
  let orphan = file & ".tmp.ABC123"
  assert replaceAtomicFile(orphan, [1'u8, 2, 3], ByteLimit(3)) == AtomicFileError.None, "simulate interrupted unpublished sibling"
  assert owner.openAssuranceStore(folder, chain(), limits()).error == AssuranceStoreError.None, "owned orphan cleanup and directory sync"
  var raw = orphan
  var metadata = default(Stat)
  assert posix.lstat(raw.toCString(), metadata) != 0 and posix.errno() == ENOENT, "only unpublished sibling removed"
  assert owner.len == 1 and owner.loadAssuranceShard(first.specifier, first.request).error ==
      AssuranceStoreError.None, "published promise preserved"
proc crashes(first, second: VerifiedAvailabilityTransfer) =
  ## Exact child-process stops and SIGKILL distinguish durable prefixes from a returned error or a simulated restart.
  for boundary in [4096, 0, 1]:
    let folder = name("crash-" & $boundary)
    clean(folder)
    defer: clean(folder)
    var owner = default(AssuranceStore)
    defer: discard owner.close()
    assert owner.createAssuranceStore(folder, chain(), limits()).error == AssuranceStoreError.None, "crash namespace"
    assert owner.rememberAssuranceShard(first, AssuranceTime(1000)).error ==
        AssuranceStoreError.None, "durable prefix before child"
    assert owner.close().error == AssuranceStoreError.None, "parent owns no writer before fork"
    resetIo()
    let child = forkCrash(syncIo, cint(boundary))
    assert child >= 0, "exact crash child created"
    if child == 0:
      # Child setup precedes observation; exit without ARC cleanup models process death with live native ownership.
      if owner.openAssuranceStore(folder, chain(), limits()).error !=
          AssuranceStoreError.None: exitCrash(81)
      if startCrash() != 0: exitCrash(82)
      if owner.rememberAssuranceShard(second, AssuranceTime(1100)).error !=
          AssuranceStoreError.None: exitCrash(83)
      exitCrash(0)
    let receipt = finishCrash()
    if boundary == 4096:
      assert receipt == crashCompleted and crashCount() == 2, "positive child reaches both real sync barriers"
    else:
      assert receipt == crashKilled and crashCount() == uint64(boundary)+1, "witnessed successful sync then SIGKILL and exact reap"
    resetIo()
    assert owner.openAssuranceStore(folder, chain(), limits()).error == AssuranceStoreError.None, "actual post-death recovery"
    assert owner.loadAssuranceShard(first.specifier, first.request).error ==
        AssuranceStoreError.None, "original committed promise survives every stop"
    if boundary == 0:
      assert owner.len == 1, "unpublished temporary cannot enter accounting"
      assert owner.loadAssuranceShard(second.specifier, second.request).error ==
          AssuranceStoreError.Missing, "data-sync stop precedes canonical filename"
    else:
      assert owner.len == 2, "directory-synced complete record survives even before a receipt returned"
      assert owner.loadAssuranceShard(second.specifier, second.request).error ==
          AssuranceStoreError.None, "restored complete bytes verified and resynchronized"
proc namespaceBounds(first: VerifiedAvailabilityTransfer) =
  ## Scan-work refusal and a missing directory cannot discard an older promise or become a valid empty archive.
  let folder = name("scan")
  clean(folder)
  defer: clean(folder)
  var owner = default(AssuranceStore)
  defer: discard owner.close()
  var policy = limits()
  policy.entries = ElementLimit(1)
  policy.scanEntries = ElementLimit(259)
  let insufficient = owner.createAssuranceStore(folder, chain(), policy)
  assert insufficient.error == AssuranceStoreError.InvalidPolicy, "configured scan budget must reopen every promised record and interrupted sibling"
  assert not owner.opened, "inconsistent scan policy cannot acquire a native namespace"
  policy.entries = ElementLimit(high(uint32))
  policy.scanEntries = ElementLimit(high(uint32))
  assert owner.createAssuranceStore(folder, chain(), policy).error ==
      AssuranceStoreError.InvalidPolicy, "maximum record count cannot wrap fixed scan overhead"
  policy.entries = ElementLimit(1)
  policy.scanEntries = ElementLimit(260)
  assert owner.createAssuranceStore(folder, chain(), policy).error == AssuranceStoreError.None, "exact bounded namespace policy"
  assert owner.rememberAssuranceShard(first, AssuranceTime(1000)).error == AssuranceStoreError.None, "bounded history"
  assert owner.close().error == AssuranceStoreError.None, "close before interrupted siblings"
  let file = location(folder, first)
  for suffix in ["ABC123", "ABC124"]:
    # These exact atomic sibling names are unpublished crash debris; the published file remains independent.
    assert replaceAtomicFile(file & ".tmp." & suffix, [0'u8], ByteLimit(1)) == AtomicFileError.None, "bounded debris fixture"
  assert owner.openAssuranceStore(folder, chain(), policy).error ==
      AssuranceStoreError.LimitExceeded, "whole scan cap is not an accepted prefix"
  assert not owner.opened, "scan refusal releases its writer"
  assert decodeAssuranceRecord(readBoundedFile(file, policy.record.bytes).value, chain(),
      policy.record).error == AssuranceRecordError.None, "published data unchanged by bounded cleanup"
  assert owner.openAssuranceStore(folder, chain(), policy).error == AssuranceStoreError.None, "bounded retry finishes remaining debris"
  assert owner.len == 1, "no promise evicted by work refusal"
  assert owner.close().error == AssuranceStoreError.None, "close before missing bucket"
  var absent = folder & "/" & (if first.specifier.erasureRoot.bytes[0] == 0: "01" else: "00")
  assert posix.rmdir(absent.toCString()) == 0, "remove only empty test bucket"
  assert owner.openAssuranceStore(folder, chain(), policy).error ==
      AssuranceStoreError.InvalidNamespace, "missing directory is not empty history"
  assert not owner.opened, "failed recovery leaves no live lease"
  assert posix.mkdir(absent.toCString(), Mode(0o700)) == 0, "repair empty bucket"
  assert owner.openAssuranceStore(folder, chain(), policy).error == AssuranceStoreError.None, "reopen exact repaired namespace"
  assert owner.loadAssuranceShard(first.specifier, first.request).error == AssuranceStoreError.None, "original promise after repair"
proc cycle(owner: var AssuranceStore, first: VerifiedAvailabilityTransfer) =
  ## Every full file read, proof owner, synchronization path and detached serving copy retires before allocation comparison.
  let restored = owner.loadAssuranceShard(first.specifier, first.request)
  assert restored.error == AssuranceStoreError.None, "ARC restore"
  assert restored.value.storedTransfer(ByteLimit(16000000)).error == AvailabilityTransferError.None, "ARC serving copy"
proc main() =
  ## Native IO observer retains real files and barriers except for the exact explicitly armed failure.
  resetIo()
  let source = computedAvailability(0)
  let first = shard(source, 0)
  let second = shard(source, 1)
  let third = shard(source, 2)
  ordinary(first, second, third)
  conflicts(first)
  failures(first, second)
  restartDamage(first)
  crashes(first, second)
  namespaceBounds(first)
  let folder = name("arc")
  clean(folder)
  defer: clean(folder)
  var owner = default(AssuranceStore)
  defer: discard owner.close()
  assert owner.createAssuranceStore(folder, chain(), limits()).error == AssuranceStoreError.None, "ARC namespace"
  assert owner.rememberAssuranceShard(first, AssuranceTime(1000)).error == AssuranceStoreError.None, "ARC committed record"
  cycle(owner, first)
  let before = getOccupiedMem()
  for index in 0..<1000:
    # Repeated real restart-data proof/sync/serve scopes retain constant resident store metadata.
    cycle(owner, first)
  let after = getOccupiedMem()
  assert before == after, "durable assurance store ARC release"
  recordArcRelease("jamnp_assurance_store", 1000, before, after)
  echo "JAMNP-S assurance store passed"
main()
