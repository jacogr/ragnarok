# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently replayed candidate/staging prefixes constrain explicit sealed and partial cleanup authority.
# @@Verification={"arc":"storage_paged_cleanup_arc_release"}
import std/[assertions, syncio]
import ../../support/[paged_native_fixture, paged_reference, storage_io, arc_evidence]
import ../../../src/storage/[paged_store, paged_io, paged_codec, paged_stream, managed_manifest,
  light_delta, file_errors, durability, light_state_cache, state_proof]
import ../../../src/codec/bounded
proc path(label: string): string =
  ## Each process/trial uses a new test-owned namespace without directory sweeps.
  "paged-cleanup-" & $storageProcessId() & "-" & label
proc writePrefix(path: string, bytes: seq[byte], count: int) =
  ## Independent fixture writes deliberately stop inside pages and digest/checksum words.
  var text = newString(count)
  for index in 0..<count: text[index] = char(bytes[index])
  try:
    writeFile(path, text)
  except:
    assert false, "write partial fixture"
proc existsNative(path: cstring, mode: cint): cint {.importc: "access", cdecl,
    header: "<unistd.h>".}
  ## Observe only exact test-owned names; directory scans never grant cleanup authority.
proc exists(path: string): bool =
  ## Keep absence distinct from an explicitly created zero-byte candidate.
  var name = path
  existsNative(name.toCString(), 0) == 0
proc seed(writer: var PagedWriter, directory: string, fixture: PagedNativeFixture) =
  ## Start every independent trial from a confirmed source and exact expected policies.
  assert initializePagedWriter(writer, directory, fixture.config, fixture.records.nativeProducer,
    uint64(fixture.records.len), fixture.payload).error == PagedNativeError.None
proc target(fixture: PagedNativeFixture): PagedHeader =
  ## Target root/counts/sequence come from fixture authority, never partially authored candidate metadata.
  initPagedHeader(fixture.config.chain, fixture.config.root, ManagedEpoch(2), LightDeltaSequence(1),
    uint64(fixture.records.len), fixture.payload, fixture.config.limits.dataset).value
proc reference(fixture: PagedNativeFixture): PagedReference =
  ## Recompute the complete target independently before cutting arbitrary native prefixes.
  result = pagedReference(fixture.config.chain, fixture.config.root, fixture.records)
  result.bytes.put(88, 2)
  result.bytes.put(96, 1)
  result.recommit()
proc sealed(fixture: PagedNativeFixture) =
  ## A live sealed capability can be discarded without a caller producer, then the same next epoch can be authored safely.
  let directory = path("sealed")
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  defer:
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  seed(writer, directory, fixture)
  let source = writer.selected.value
  assert preparePagedReplacement(writer, candidate, fixture.records.nativeProducer,
    uint64(fixture.records.len), fixture.payload).error == PagedNativeError.None
  let removed = discardPagedCandidate(writer, candidate, source)
  assert removed.error == PagedNativeError.None and not removed.value.alreadyAbsent
  assert removed.value.durability == StorageDurability.FileAndDirectorySynced
  assert not candidate.opened
  assert not exists(directory & "/" & epochName(ManagedEpoch(2)).value)
  assert writer.selected.value.bytes == source.bytes
  assert preparePagedReplacement(writer, candidate, fixture.records.nativeProducer,
    uint64(fixture.records.len), fixture.payload).error == PagedNativeError.None
  assert writer.publish(candidate).error == PagedNativeError.None
  assert writer.close == FileError.None
proc sealedStaging(fixture: PagedNativeFixture) =
  ## Full seals can validate staging directly; a failed comparison never grants authority on a second attempt.
  for bad in [false, true]:
    let directory = path("sealed-staging-" & $bad)
    var writer = default(PagedWriter)
    var candidate = default(PagedCandidate)
    defer:
      resetIo()
      if candidate.opened: discard candidate.close
      if writer.opened: discard writer.close
    seed(writer, directory, fixture)
    let source = writer.selected.value
    assert preparePagedReplacement(writer, candidate, fixture.records.nativeProducer,
      uint64(fixture.records.len), fixture.payload).error == PagedNativeError.None
    var expected = reference(fixture)
    if bad: expected.manifest[0] = expected.manifest[0] xor 1
    writePrefix(directory & "/CURRENT.next", expected.manifest, 73)
    resetIo()
    if bad:
      for retry in 0..<2:
        let refused = discardPagedCandidate(writer, candidate, source)
        assert refused.error == PagedNativeError.FileFailure and refused.fileError ==
            FileError.RecoveryMismatch
        assert ioCalls(unlinkIo) == 0
      assert exists(directory & "/" & epochName(ManagedEpoch(2)).value)
      resetIo()
      assert candidate.close == FileError.None
    else:
      assert discardPagedCandidate(writer, candidate, source).error == PagedNativeError.None
      assert not exists(directory & "/CURRENT.next")
    resetIo()
    assert writer.close == FileError.None
proc partial(fixture: PagedNativeFixture, bytes, pending: int) =
  ## Complete replay preflights both files before any unlink and never grants publication authority to partial bytes.
  let directory = path("prefix-" & $bytes & "-" & $pending)
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  defer:
    resetIo()
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  seed(writer, directory, fixture)
  let source = writer.selected.value
  let expected = reference(fixture)
  let epoch = directory & "/" & epochName(ManagedEpoch(2)).value
  if bytes >= 0: writePrefix(epoch, expected.bytes, bytes)
  if pending >= 0: writePrefix(directory & "/CURRENT.next", expected.manifest, pending)
  assert preparePagedCleanup(writer, candidate, source, target(fixture),
      fixture.records.nativeProducer).error == PagedNativeError.None
  var moved = move(candidate)
  assert not candidate.opened and moved.opened
  candidate = move(moved)
  assert not moved.opened
  assert writer.publish(candidate).error == PagedNativeError.InvalidCandidate
  let removed = discardPagedCandidate(writer, candidate, source)
  assert removed.error == PagedNativeError.None and removed.value.alreadyAbsent == (bytes < 0)
  assert not candidate.opened and not exists(epoch) and not exists(directory & "/CURRENT.next")
  assert writer.selected.value.bytes == source.bytes
  assert writer.close == FileError.None
proc cycle(writer: var PagedWriter, fixture: PagedNativeFixture) =
  ## All anonymous scratch and prepared owner resources retire before each ARC sample.
  var candidate = default(PagedCandidate)
  let source = writer.selected.value
  assert preparePagedCleanup(writer, candidate, source, target(fixture),
      fixture.records.nativeProducer).error == PagedNativeError.None
  assert discardPagedCandidate(writer, candidate, source).value.alreadyAbsent
proc captured(path: string): string =
  ## Preserve exact forensic bytes and absence independently of any cleanup outcome.
  if not exists(path): return "absent"
  try:
    return "present:" & readFile(path)
  except:
    assert false, "capture cleanup fixture"
proc mismatches(fixture, fresh: PagedNativeFixture) =
  ## Wrong target authority and mismatched pending prefixes cannot delete even an otherwise matching epoch.
  for mode in 0..<5:
    let directory = path("mismatch-" & $mode)
    var writer = default(PagedWriter)
    var candidate = default(PagedCandidate)
    defer:
      resetIo()
      if candidate.opened: discard candidate.close
      if writer.opened: discard writer.close
    seed(writer, directory, fixture)
    let source = writer.selected.value
    var expected = reference(fixture)
    let epoch = directory & "/" & epochName(ManagedEpoch(2)).value
    writePrefix(epoch, expected.bytes, 4097)
    if mode == 0: expected.manifest[192] = expected.manifest[192] xor 1
    if mode == 2: expected.bytes[57] = expected.bytes[57] xor 1
    if mode == 2: writePrefix(epoch, expected.bytes, 4097)
    if mode == 3:
      # A complete expected artifact plus one trailing byte is never a recoverable prefix.
      expected.bytes.add(0)
      writePrefix(epoch, expected.bytes, expected.bytes.len)
    if mode == 4: expected.manifest.add(0)
    writePrefix(directory & "/CURRENT.next", expected.manifest, expected.manifest.len)
    let before = [captured(epoch), captured(directory & "/CURRENT.next"), captured(directory & "/CURRENT")]
    resetIo()
    let authority = if mode == 1: fresh else: fixture
    let header = if mode == 1:
      initPagedHeader(authority.config.chain, authority.config.root, ManagedEpoch(2),
          LightDeltaSequence(0),
        uint64(authority.records.len), authority.payload, authority.config.limits.dataset).value
    else: target(authority)
    let refused = preparePagedCleanup(writer, candidate, source, header,
        authority.records.nativeProducer)
    assert refused.error == PagedNativeError.FileFailure
    if mode == 4: assert refused.fileError == FileError.LimitExceeded
    else: assert refused.fileError == FileError.RecoveryMismatch
    assert not candidate.opened and ioCalls(unlinkIo) == 0
    resetIo()
    assert before == [captured(epoch), captured(directory & "/CURRENT.next"), captured(directory & "/CURRENT")]
    assert writer.close == FileError.None
proc stale(fixture: PagedNativeFixture) =
  ## Neither reopened writer incarnations nor a newly created inode can be removed by a passive old capability.
  for mode in 0..<3:
    let directory = path("stale-" & $mode)
    var writer = default(PagedWriter)
    var candidate = default(PagedCandidate)
    var authored = default(PagedCandidate)
    defer:
      resetIo()
      if authored.opened: discard authored.close
      if candidate.opened: discard candidate.close
      if writer.opened: discard writer.close
    seed(writer, directory, fixture)
    let source = writer.selected.value
    assert preparePagedCleanup(writer, candidate, source, target(fixture),
        fixture.records.nativeProducer).error == PagedNativeError.None
    if mode == 0:
      # Equal physical/root counters after reopen do not restore original writer incarnation.
      assert writer.close == FileError.None
      assert openPagedWriter(writer, directory, fixture.config).error == PagedNativeError.None
    elif mode == 1:
      # Captured absence cannot claim a next-epoch artifact created later under this same writer.
      assert preparePagedReplacement(writer, authored, fixture.records.nativeProducer,
        uint64(fixture.records.len), fixture.payload).error == PagedNativeError.None
    else:
      # Unknown new staging bytes block deletion before any namespace mutation.
      writePrefix(directory & "/CURRENT.next", reference(fixture).manifest, 1)
    resetIo()
    let refused = discardPagedCandidate(writer, candidate, source)
    assert refused.error != PagedNativeError.None and ioCalls(unlinkIo) == 0
    resetIo()
    assert writer.selected.value.bytes == source.bytes
    assert candidate.close == FileError.None
    if authored.opened: assert authored.close == FileError.None
    assert writer.close == FileError.None
proc lateMutation(fixture: PagedNativeFixture) =
  ## A prepared staging inode/version is checked again before deleting either captured file.
  let directory = path("late-mutation")
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  defer:
    resetIo()
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  seed(writer, directory, fixture)
  let source = writer.selected.value
  var expected = reference(fixture)
  let epoch = directory & "/" & epochName(ManagedEpoch(2)).value
  writePrefix(epoch, expected.bytes, 100)
  writePrefix(directory & "/CURRENT.next", expected.manifest, 193)
  assert preparePagedCleanup(writer, candidate, source, target(fixture),
      fixture.records.nativeProducer).error == PagedNativeError.None
  expected.manifest[192] = expected.manifest[192] xor 1
  writePrefix(directory & "/CURRENT.next", expected.manifest, 193)
  resetIo()
  assert discardPagedCandidate(writer, candidate, source).error == PagedNativeError.FileFailure
  assert ioCalls(unlinkIo) == 0 and exists(epoch)
  resetIo()
  assert candidate.close == FileError.None and writer.close == FileError.None
proc rootModes(fixture, fresh: PagedNativeFixture) =
  ## Explicit root-advance cleanup preserves sequence; compaction replay additionally requires exact source knowledge.
  for mode in 0..<3:
    let directory = path("root-mode-" & $mode)
    var writer = default(PagedWriter)
    var candidate = default(PagedCandidate)
    defer:
      if candidate.opened: discard candidate.close
      if writer.opened: discard writer.close
    seed(writer, directory, fixture)
    let source = writer.selected.value
    let authority = if mode == 0: fresh else: fixture
    let records = if mode != 1: authority.records else: @[authority.records[0], authority.records[1]]
    let payload = if mode != 1: authority.payload else:
      authority.payload-41-uint64(authority.records[2].proof.nodes.len)*64
    let header = initPagedHeader(authority.config.chain, authority.config.root, ManagedEpoch(2),
      LightDeltaSequence(0), uint64(records.len), payload, authority.config.limits.dataset).value
    var expected = pagedReference(authority.config.chain, authority.config.root, records)
    expected.bytes.put(88, 2)
    expected.recommit()
    writePrefix(directory & "/" & epochName(ManagedEpoch(2)).value, expected.bytes, 120)
    let replayed = preparePagedCleanup(writer, candidate, source, header, records.nativeProducer)
    if mode == 0:
      # Destination identity is an independent caller expectation; no source proof is implicitly carried forward.
      assert replayed.error == PagedNativeError.None
      assert discardPagedCandidate(writer, candidate, source).error == PagedNativeError.None
      assert preparePagedAdvance(writer, candidate, fresh.config.root, fresh.records.nativeProducer,
        uint64(fresh.records.len), fresh.payload).error == PagedNativeError.None
      assert writer.publish(candidate).error == PagedNativeError.None
      assert uint64(writer.selected.value.sequence) == 0
    elif mode == 2:
      # An exact replay of source knowledge remains a valid compaction cleanup witness.
      assert replayed.error == PagedNativeError.None
      assert discardPagedCandidate(writer, candidate, source).error == PagedNativeError.None
      assert writer.selected.value.bytes == source.bytes
    else:
      # Same-root/same-sequence recovery cannot reinterpret discarded query knowledge as compaction.
      assert replayed.error == PagedNativeError.InvalidTransition and not candidate.opened
    assert writer.close == FileError.None
proc faultTrial(fixture: PagedNativeFixture, phase: int, operation: cint, skip: int): array[5, uint64] =
  ## Each prepare/discard syscall fault must fire; fresh replay after close/reopen completes any confirmed partial unlink progress.
  result = default(array[5, uint64])
  let directory = path("fault-" & $phase & "-" & $operation & "-" & $skip)
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  defer:
    resetIo()
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  seed(writer, directory, fixture)
  let source = writer.selected.value
  let expected = reference(fixture)
  let epoch = directory & "/" & epochName(ManagedEpoch(2)).value
  writePrefix(epoch, expected.bytes, expected.bytes.len-17)
  writePrefix(directory & "/CURRENT.next", expected.manifest, 73)
  if phase == 1:
    assert preparePagedCleanup(writer, candidate, source, target(fixture),
        fixture.records.nativeProducer).error == PagedNativeError.None
  resetIo()
  if operation != 0: armIo(operation, cint(skip), 1, failedIo)
  if phase == 0:
    # Preparation can expose no cleanup owner after failed scratch/replay/prefix validation or retirement.
    let prepared = preparePagedCleanup(writer, candidate, source, target(fixture),
        fixture.records.nativeProducer)
    if operation == 0: assert prepared.error == PagedNativeError.None
    else: assert prepared.error != PagedNativeError.None and not candidate.opened
  else:
    # Confirmed deletion survives only subsequent descriptor-retirement failure, with an explicit separate cause.
    let removed = discardPagedCandidate(writer, candidate, source)
    if operation == 0: assert removed.error == PagedNativeError.None
    elif removed.error == PagedNativeError.None:
      assert operation == closeIo and removed.value.retirementError == FileError.IoFailure
      assert not candidate.opened
  if operation == 0:
    result = [ioCalls(readIo), ioCalls(writeIo), ioCalls(lockIo), ioCalls(closeIo), ioCalls(syncIo)]
    if phase == 1: result[1] = ioCalls(unlinkIo)
  else: assert pendingIo() == 0
  resetIo()
  if candidate.opened: assert candidate.close == FileError.None
  assert writer.close == FileError.None
  assert openPagedWriter(writer, directory, fixture.config).error == PagedNativeError.None
  assert writer.selected.value.bytes == source.bytes
  assert preparePagedCleanup(writer, candidate, source, target(fixture),
      fixture.records.nativeProducer).error == PagedNativeError.None
  assert discardPagedCandidate(writer, candidate, source).error == PagedNativeError.None
  assert not exists(epoch) and not exists(directory & "/CURRENT.next")
  assert writer.close == FileError.None
proc faultSchedule(fixture: PagedNativeFixture) =
  ## Only actual observed operations are scheduled; syscall absence is not silently counted as a successful injected case.
  for phase in 0..<2:
    let counts = faultTrial(fixture, phase, 0, 0)
    let operations = if phase == 0: [readIo, writeIo, lockIo, closeIo, syncIo]
      else: [readIo, unlinkIo, lockIo, closeIo, syncIo]
    for index in 0..<operations.len:
      assert counts[index] < 1000
      if (phase == 0 and index == 4) or (phase == 1 and index == 2):
        # Replay scratch is intentionally not synchronized; existing held pins are not reacquired during discard.
        assert counts[index] == 0
      else:
        assert counts[index] > 0
        for skip in 0..<int(counts[index]): discard faultTrial(fixture, phase, operations[index], skip)
proc bootstrap(fixture: PagedNativeFixture) =
  ## Reproducible failed bootstrap prefixes can resume only while CURRENT remains absent under an existing stable LOCK.
  for operation in [writeIo, renameIo]:
    let directory = path("bootstrap-" & $operation)
    var writer = default(PagedWriter)
    defer:
      resetIo()
      if writer.opened: discard writer.close
    resetIo()
    armIo(operation, 0, 1, failedIo)
    let failed = initializePagedWriter(writer, directory, fixture.config,
      fixture.records.nativeProducer,
      uint64(fixture.records.len), fixture.payload)
    assert failed.error != PagedNativeError.None and pendingIo() == 0
    resetIo()
    assert writer.opened and not exists(directory & "/CURRENT")
    assert writer.close == FileError.None
    let resumed = resumePagedInitialization(writer, directory, fixture.config,
      fixture.records.nativeProducer,
      uint64(fixture.records.len), fixture.payload)
    assert resumed.error == PagedNativeError.None and resumed.value.writerUsable
    assert uint64(writer.selected.value.epoch) == 1 and uint64(writer.selected.value.sequence) == 0
    assert writer.close == FileError.None
    resetIo()
    let refused = resumePagedInitialization(writer, directory, fixture.config,
      fixture.records.nativeProducer,
      uint64(fixture.records.len), fixture.payload)
    assert refused.error == PagedNativeError.FileFailure and refused.fileError ==
        FileError.AlreadyExists
    assert ioCalls(writeIo) == 0 and ioCalls(unlinkIo) == 0 and ioCalls(renameIo) == 0
    assert writer.selected.error == PagedNativeError.RecoveryRequired
    resetIo()
    assert writer.close == FileError.None
proc selectedUncertainty(fixture: PagedNativeFixture) =
  ## A rename followed by directory-sync uncertainty may select the target; stale recovery authority never deletes it.
  let directory = path("selected-uncertainty")
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  defer:
    resetIo()
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  seed(writer, directory, fixture)
  let source = writer.selected.value
  assert preparePagedReplacement(writer, candidate, fixture.records.nativeProducer,
    uint64(fixture.records.len), fixture.payload).error == PagedNativeError.None
  resetIo()
  armIo(syncIo, 1, 1, failedIo)
  let uncertain = writer.publish(candidate)
  assert uncertain.error == PagedNativeError.FileFailure and uncertain.fileError ==
      FileError.PublishedUnsynced
  assert pendingIo() == 0
  resetIo()
  assert candidate.close == FileError.None and writer.close == FileError.None
  assert openPagedWriter(writer, directory, fixture.config).error == PagedNativeError.None
  assert uint64(writer.selected.value.epoch) == 2
  resetIo()
  assert preparePagedCleanup(writer, candidate, source, target(fixture),
      fixture.records.nativeProducer).error == PagedNativeError.StaleView
  assert ioCalls(unlinkIo) == 0 and exists(directory & "/" & epochName(ManagedEpoch(2)).value)
  resetIo()
  assert writer.close == FileError.None

proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Provider failures retain checked source authority independently of IO poison.
proc failHashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Select a genuine late replay hash without substituting a production provider.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Baseline observations size bounded provider-failure controls.
proc providerAndQuota(fixture: PagedNativeFixture) =
  ## Early/late provider refusals and preflight write quota cannot create a deletion capability or alter source/candidates.
  var total = 0.cint
  block:
    var writer = default(PagedWriter)
    var candidate = default(PagedCandidate)
    seed(writer, path("provider-baseline"), fixture)
    let source = writer.selected.value
    resetHash(0)
    assert preparePagedCleanup(writer, candidate, source, target(fixture),
        fixture.records.nativeProducer).error == PagedNativeError.None
    total = hashCalls()
    assert total > 2
    resetHash(0)
    assert candidate.close == FileError.None and writer.close == FileError.None
  for skip in [0.cint, total div 2, total-1]:
    var writer = default(PagedWriter)
    var candidate = default(PagedCandidate)
    let directory = path("provider-" & $skip)
    seed(writer, directory, fixture)
    let source = writer.selected.value
    resetHash(0)
    failHashAfter(skip)
    let refused = preparePagedCleanup(writer, candidate, source, target(fixture),
        fixture.records.nativeProducer)
    assert refused.error == PagedNativeError.StreamFailure and refused.streamError ==
        PagedStreamError.BackendFailure
    assert hashCalls() == skip+1 and not candidate.opened
    resetHash(0)
    assert writer.selected.value.bytes == source.bytes
    assert writer.close == FileError.None
  block:
    var writer = default(PagedWriter)
    var candidate = default(PagedCandidate)
    let directory = path("quota")
    seed(writer, directory, fixture)
    assert writer.close == FileError.None
    var limits = fixture.config
    limits.limits.work.writeBytes = ByteLimit(0)
    assert openPagedWriter(writer, directory, limits).error == PagedNativeError.None
    let source = writer.selected.value
    resetIo()
    let refused = preparePagedCleanup(writer, candidate, source, target(fixture),
        fixture.records.nativeProducer)
    assert refused.error == PagedNativeError.StreamFailure and refused.streamError ==
        PagedStreamError.LimitExceeded
    assert ioCalls(writeIo) == 0 and ioCalls(unlinkIo) == 0 and not candidate.opened
    resetIo()
    assert writer.selected.value.bytes == source.bytes and writer.close == FileError.None
proc changingReplay(records: seq[LightStateProof]): PagedProducer =
  ## Test-only stable individual passes deliberately change one valid empty-root query between separate builds.
  var builds = 0
  proc next(pass: int, ordinal: uint64, output: var LightStateProof): PagedProducerStep {.closure.} =
    if pass == 0 and ordinal == 0: inc builds
    if ordinal >= uint64(records.len): return PagedProducerStep.End
    output = records[int(ordinal)]
    if builds > 1 and ordinal == 0: output.key = pagedKey(1)
    PagedProducerStep.Item
  next
proc changedBootstrap() =
  ## Resume binds new authorship to the complete replay witness, not just independent validity at the same JAM root.
  let config = PagedNativeConfig(limits: pagedPolicy())
  let records = @[LightStateProof(key: pagedKey(0), proof: StateProof()),
    LightStateProof(key: pagedKey(128), proof: StateProof())]
  let directory = path("changed-bootstrap")
  var writer = default(PagedWriter)
  defer:
    resetIo()
    if writer.opened: discard writer.close
  resetIo()
  armIo(writeIo, 0, 1, failedIo)
  assert initializePagedWriter(writer, directory, config, records.nativeProducer, 2, 82).error !=
      PagedNativeError.None
  assert pendingIo() == 0
  resetIo()
  assert writer.close == FileError.None
  let refused = resumePagedInitialization(writer, directory, config, changingReplay(records), 2, 82)
  assert refused.error == PagedNativeError.StreamFailure and refused.streamError ==
      PagedStreamError.ChangedInput
  assert not exists(directory & "/CURRENT")
  assert exists(directory & "/" & epochName(ManagedEpoch(1)).value)
  assert writer.selected.error == PagedNativeError.RecoveryRequired
  assert writer.close == FileError.None

proc main() =
  ## Native positive controls first qualify actual tmpfile/fcntl/close SDK bindings and directory-relative pins.
  let fixture = nativeFixture(7)
  sealed(fixture)
  sealedStaging(fixture)
  let expected = reference(fixture)
  for count in [-1, 0, 1, 119, 120, 4095, 4096, 4097, 8191, 8192,
      expected.bytes.len-33, expected.bytes.len-32, expected.bytes.len-31, expected.bytes.len-1,
      expected.bytes.len]:
    partial(fixture, count, 0)
  for count in 0..193: partial(fixture, 73, count)
  partial(fixture, -1, -1)
  mismatches(fixture, nativeFixture(9))
  stale(fixture)
  lateMutation(fixture)
  rootModes(fixture, nativeFixture(9))
  faultSchedule(fixture)
  bootstrap(fixture)
  selectedUncertainty(fixture)
  providerAndQuota(fixture)
  changedBootstrap()
  var writer = default(PagedWriter)
  seed(writer, path("cycles"), fixture)
  cycle(writer, fixture)
  let before = getOccupiedMem()
  for index in 0..<1000: cycle(writer, fixture)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_paged_cleanup", 1000, before, after)
  assert writer.close == FileError.None
  echo "PASS paged cleanup: sealed capabilities, replay-bound exact prefixes, staging preflight and explicit durable retirement"
main()
