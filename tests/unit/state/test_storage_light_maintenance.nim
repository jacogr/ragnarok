# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent threshold/range models and real faults qualify exact-source maintenance receipts, bounded continuation and maximum counters.
# @@Verification={"arc":"storage_light_maintenance_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, storage_io, storage_light_root, storage_light_journal, storage_light_maintenance]
import ../../../src/storage/[light_snapshot, light_state_cache, light_journal_cache,
  light_journal_manifest,
  light_delta, managed_io, managed_manifest, file_errors]
import ../../../src/codec/bounded
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Separate pure policy decisions and metadata preparation from selected-head revalidation.
proc refuseAfter(count: cint) {.importc: "ro_blake_after", cdecl.}
  ## Consume each preparation hash and a cleanup-only validation refusal independently.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## No-action and invalid-source preparation performs no crypto.
proc cycle(owner: LightJournalCache) =
  ## Copied compaction plans and late metadata refusal retire all private state before each ARC sample.
  let prepared = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value,
      maintenanceLimits()).value
  let copied = prepared
  assert copied.compactionNeeded and uint64(copied.retiredCount) == 1, "copied maintenance decision"
  refuseAfter(1)
  let refused = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value,
      maintenanceLimits())
  assert refused.error == FileError.BackendFailure, "late maintenance metadata refusal"
  resetHash(0)
proc normal(fixture: LightRootFixture) {.raises.} =
  ## Confirm compaction before retirement, then prove exact progress, no-action idempotence and a following retained admission.
  let path = "maintenance-normal-" & $storageProcessId()
  let held = seedLightMaintenance(path, fixture)
  var owner = default(LightJournalCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
  resetIo()
  resetHash(0)
  let plan = prepareLightMaintenance(owner, ManagedEpoch(1), LightDeltaSequence(1),
      maintenanceLimits()).value
  assert plan.initialized and plan.compactionNeeded and uint64(plan.retiredCount) == 1 and uint64(
      plan.firstRetiredEpoch) == 1, "exact threshold and retirement range"
  assert calls() == 2 and ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "only compaction metadata hashes before IO"
  for index in 0..<10: cycle(owner)
  let before = getOccupiedMem()
  for index in 0..<1000: cycle(owner)
  let after = getOccupiedMem()
  assert before == after, "maintenance candidates retain no native lease or image chain"
  recordArcRelease("storage_light_maintenance", 1000, before, after)
  for skip in 0..<2:
    refuseAfter(cint(skip))
    assert prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value,
        maintenanceLimits()).error == FileError.BackendFailure
    assert calls() == cint(skip+1), "exact maintenance metadata refusal"
  resetHash(0)
  resetIo()
  let receipt = owner.maintain(plan).value
  assert receipt.compacted and uint64(receipt.previousEpoch) == 1 and uint64(receipt.epoch) == 2 and
      uint64(receipt.sequence) == 1
  assert receipt.retirement == FileError.None and receipt.cleanup == FileError.None and uint64(
      receipt.retired) == 1 and uint64(receipt.nextRetiredEpoch) == 2
  assert ioCalls(writeIo) == 3 and ioCalls(syncIo) == 11 and ioCalls(renameIo) == 1 and ioCalls(
      unlinkIo) == 2, "compaction plus exactly one guarded pair job"
  assert owner.preparedSnapshot.value.encodedBytes == held.encodedBytes, "maintenance preserves exact proof knowledge"
  assert owner.maintain(plan).error == FileError.StaleView and owner.discardUnselectedMaintenance(
      plan) == FileError.InvalidRetention, "selected compaction cannot be replayed or discarded"
  var limits = maintenanceLimits()
  limits.first = receipt.nextRetiredEpoch
  resetHash(0)
  resetIo()
  let idle = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value, limits).value
  assert not idle.compactionNeeded and uint64(idle.retiredCount) == 0, "empty selected log cannot repeatedly compact"
  assert owner.discardUnselectedMaintenance(idle) == FileError.InvalidBatch, "idle plan has no candidate discard authority"
  let unchanged = owner.maintain(idle).value
  assert not unchanged.compacted and unchanged.cleanup == FileError.None and uint64(
      unchanged.epoch) == 2
  assert calls() == 0 and ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0 and ioCalls(unlinkIo) == 0, "idle maintenance is pure"
  let retention = LightRetentionLimits(items: ElementLimit(3), valueBytes: ByteLimit(128),
      bytes: ByteLimit(8192), entries: ElementLimit(3), evictions: ElementLimit(1))
  assert owner.admitRetained([fixture.sourceProofs[1]], retention).error == FileError.None, "retained admission remains usable after maintenance"
  let second = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value, limits).value
  assert owner.maintain(second).value.cleanup == FileError.None and uint64(owner.epoch.value) ==
      3 and uint64(owner.sequence.value) == 2
  assert held.cache.lookup(lightKey(0)).value.bytes[0] == 7, "reader outlives old-epoch deletion"
  assert owner.close == FileError.None
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None and uint64(
      owner.sequence.value) == 2
  assert owner.close == FileError.None
  retireRootEpoch(path, ManagedEpoch(3))
  retireLightJournal(path)
proc model(fixture: LightRootFixture) {.raises.} =
  ## Enumerate retirement eligibility independently over selected epoch four and prospective compacted epoch five.
  let path = "maintenance-model-" & $storageProcessId()
  discard seedLightMaintenance(path, fixture)
  var owner = default(LightJournalCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
  for index in 0..<3:
    let prepared = prepareLightCompaction(owner, owner.epoch.value, owner.sequence.value).value
    assert owner.compact(prepared).error == FileError.None
  assert owner.update([], []).error == FileError.None and uint64(owner.epoch.value) == 4
  resetIo()
  for compact in [false, true]:
    for keep in 0..6:
      for first in 1..5:
        for jobs in 0..6:
          let target = if compact: 5 else: 4
          let limits = LightMaintenanceLimits(frames: ElementLimit(ord(compact)),
              first: ManagedEpoch(first), epochs: ElementLimit(jobs), keep: ElementLimit(keep))
          let plan = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value, limits)
          if jobs > 0 and first > target:
            assert plan.error == FileError.InvalidRetention, "future cursor refusal"
          else:
            var expected = 0
            for epoch in first..<target:
              if target-epoch > keep and expected < jobs: inc expected
            assert plan.error == FileError.None and plan.value.compactionNeeded == compact
            assert uint64(plan.value.retiredCount) == uint64(expected), "independent bounded retirement model"
            let cursor = if jobs == 0: 0 else: first
            assert uint64(plan.value.firstRetiredEpoch) == uint64(cursor), "disabled sweep normalizes its unused cursor"
  assert ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0 and ioCalls(unlinkIo) == 0, "all model preparation has no IO"
  var bytes = maintenanceLimits()
  bytes.frames = ElementLimit(0)
  bytes.bytes = ByteLimit(1)
  assert prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value,
      bytes).value.compactionNeeded, "frame-byte trigger excludes fixed anchor"
  resetHash(0)
  for mode in 0..3:
    var invalid = maintenanceLimits()
    if mode == 0: invalid.frames = ElementLimit(65)
    elif mode == 1: invalid.bytes = ByteLimit(65536)
    elif mode == 2: invalid.first = ManagedEpoch(0)
    else: invalid.first = ManagedEpoch(6)
    let error = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value, invalid).error
    assert error == (if mode < 2: FileError.LimitExceeded else: FileError.InvalidRetention)
  assert prepareLightMaintenance(owner, ManagedEpoch(3), owner.sequence.value, bytes).error ==
      FileError.StaleView
  assert prepareLightMaintenance(owner, owner.epoch.value, LightDeltaSequence(0), bytes).error ==
      FileError.StaleView
  assert calls() == 0, "invalid policy/source refuses before hashing"
  var sweep = LightMaintenanceLimits(first: ManagedEpoch(1), epochs: ElementLimit(3))
  let prepared = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value, sweep).value
  resetIo()
  armIo(unlinkIo, 2, 1, failedIo)
  let partial = owner.maintain(prepared).value
  assert pendingIo() == 0 and partial.cleanup == FileError.IoFailure and uint64(partial.retired) ==
      1 and uint64(partial.nextRetiredEpoch) == 2, "partial multi-pair sweep reports exact unfinished cursor"
  resetIo()
  sweep.first = partial.nextRetiredEpoch
  sweep.epochs = ElementLimit(2)
  let continued = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value, sweep).value
  let completed = owner.maintain(continued).value
  assert completed.cleanup == FileError.None and uint64(completed.retired) == 2 and uint64(
      completed.nextRetiredEpoch) == 4
  assert owner.close == FileError.None
  retireRootEpoch(path, ManagedEpoch(4))
  retireLightJournal(path)
proc stale(fixture: LightRootFixture) {.raises.} =
  ## Exact policy, ordinary append and same-image physical/root return cycles refuse a previously prepared action without IO.
  let path = "maintenance-stale-" & $storageProcessId()
  let image = seedLightMaintenance(path, fixture)
  var owner = default(LightJournalCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert owner.maintain(default(PreparedLightMaintenance)).error == FileError.Uninitialized
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
  let plan = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value,
      maintenanceLimits()).value
  assert owner.close == FileError.None
  var changed = fixture.oldConfig
  changed.journal.frame.items = ElementLimit(3)
  assert openLightJournalCache(owner, path, changed) == FileError.None
  resetIo()
  resetHash(0)
  assert owner.maintain(plan).error == FileError.InvalidBatch and calls() == 0 and ioCalls(
      writeIo) == 0
  assert owner.close == FileError.None
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
  assert owner.update([], []).error == FileError.None
  resetIo()
  assert owner.maintain(plan).error == FileError.StaleView and ioCalls(writeIo) == 0, "same-image ordinary append stales maintenance"
  let compact = prepareLightCompaction(owner, owner.epoch.value, owner.sequence.value).value
  assert owner.compact(compact).error == FileError.None
  let original = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value, default(
      LightMaintenanceLimits)).value
  let forward = prepareLightRootAdvance(owner, owner.epoch.value, owner.sequence.value,
      fixture.newConfig.root, fixture.destination).value
  assert owner.advanceRoot(forward).error == FileError.None
  let backward = prepareLightRootAdvance(owner, owner.epoch.value, owner.sequence.value,
      fixture.oldConfig.root, image).value
  assert owner.advanceRoot(backward).error == FileError.None
  resetIo()
  assert owner.maintain(original).error == FileError.StaleView and ioCalls(unlinkIo) == 0, "equal root/image/sequence/frame-count return remains physically stale"
  for epoch in 1..3: assert owner.cleanupRetiredEpoch(ManagedEpoch(epoch)) == FileError.None
  assert owner.close == FileError.None
  retireRootEpoch(path, ManagedEpoch(4))
  retireLightJournal(path)
proc failures(fixture: LightRootFixture) {.raises.} =
  ## Publication, confirmed retirement and post-selection cleanup failures have distinct receipts and explicit safe continuation.
  for mode in 0..8:
    let path = "maintenance-fault-" & $storageProcessId() & "-" & $mode
    let held = seedLightMaintenance(path, fixture, mode >= 7)
    var owner = default(LightJournalCache)
    defer:
      resetIo()
      resetHash(0)
      if owner.opened: discard owner.close
    assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
    let plan = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value,
        maintenanceLimits()).value
    resetIo()
    if mode == 0: armIo(writeIo, 0, 1, failedIo)
    elif mode == 1: armIo(syncIo, 6, 1, failedIo)
    elif mode == 2: armIo(renameIo, 0, 1, failedIo)
    elif mode == 3: armIo(syncIo, 7, 1, failedIo)
    elif mode == 4: armIo(closeIo, 3, 1, failedIo)
    elif mode == 5: armIo(unlinkIo, 0, 1, failedIo)
    elif mode == 6: armIo(syncIo, 8, 1, failedIo)
    elif mode == 7: armIo(readIo, 0, 1, failedIo)
    else: refuseAfter(0)
    let result = owner.maintain(plan)
    if mode < 4:
      assert result.error == (if mode == 3: FileError.PublishedUnsynced else: FileError.IoFailure), "preconfirmation failure grants no receipt"
    else:
      assert result.error == FileError.None and uint64(result.value.retired) == 0 and uint64(
          result.value.nextRetiredEpoch) == 1
      assert result.value.compacted == (mode < 7) and uint64(result.value.epoch) == 2
      if mode == 4:
        assert result.value.retirement == FileError.IoFailure and result.value.cleanup ==
            FileError.RecoveryRequired
      else:
        assert result.value.retirement == FileError.None and result.value.cleanup == (if mode ==
            8: FileError.BackendFailure else: FileError.IoFailure)
    if mode < 8: assert pendingIo() == 0, "consume intended native maintenance refusal"
    if mode == 8: assert calls() == 1, "consume cleanup validation provider refusal"
    resetHash(0)
    resetIo()
    assert owner.close == FileError.None
    assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
    if uint64(owner.epoch.value) == 1:
      assert owner.discardUnselectedMaintenance(plan) == FileError.None, "explicit exact matching candidate cleanup"
      assert owner.maintain(plan).value.cleanup == FileError.None, "original exact source may retry publication after candidate discard"
    else:
      # Confirmed selection must survive cleanup errors; fresh plans continue without another empty-log compaction.
      if mode < 7: assert owner.discardUnselectedMaintenance(plan) == FileError.InvalidRetention
      let fresh = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value,
          maintenanceLimits()).value
      assert not fresh.compactionNeeded and uint64(fresh.retiredCount) == 1
      resetIo()
      assert owner.maintain(fresh).value.cleanup == FileError.None and ioCalls(syncIo) > 0, "synchronized retry includes already absent pair names"
    assert owner.preparedSnapshot.value.encodedBytes == held.encodedBytes and uint64(
        owner.sequence.value) == 1
    assert owner.close == FileError.None
    retireRootEpoch(path, ManagedEpoch(2))
    retireLightJournal(path)
proc readOnly() {.raises.} =
  ## A zero-mutation snapshot may compact a durable no-op frame without losing any independently verified knowledge.
  let fixture = rootFixture(ElementLimit(0))
  let path = "maintenance-read-only-" & $storageProcessId()
  var owner = default(LightJournalCache)
  defer:
    if owner.opened: discard owner.close
  assert initializeLightJournalCache(owner, path, fixture.oldConfig, fixture.source).error == FileError.None
  let limits = LightRetentionLimits(items: ElementLimit(4), valueBytes: ByteLimit(128),
    bytes: ByteLimit(8192), entries: ElementLimit(4))
  assert owner.admitRetained([], limits).error == FileError.None, "read-only retained no-op creates one ordinary frame"
  let plan = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value,
      maintenanceLimits()).value
  let receipt = owner.maintain(plan).value
  assert receipt.compacted and receipt.cleanup == FileError.None and uint64(receipt.sequence) == 1
  assert owner.preparedSnapshot.value.encodedBytes == fixture.source.encodedBytes, "read-only maintenance preserves all evidence and policy"
  assert owner.close == FileError.None
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
  assert owner.preparedSnapshot.value.encodedBytes == fixture.source.encodedBytes
  assert owner.close == FileError.None
  retireRootEpoch(path, ManagedEpoch(2))
  retireLightJournal(path)
proc maxima(fixture: LightRootFixture) {.raises.} =
  ## Independently authored strict selections place counters at their boundaries without unchecked production constructors.
  for maxEpoch in [false, true]:
    let path = "maintenance-max-" & $storageProcessId() & "-" & $maxEpoch
    let image = seedLightMaintenance(path, fixture)
    let epoch = ManagedEpoch(if maxEpoch: high(uint64) else: 1'u64)
    let baseline = LightDeltaSequence(if maxEpoch: 1'u64 else: high(uint64)-1)
    let selected = prepareLightJournalManifest(image, epoch, baseline, ByteLimit(
        LightJournalManifestBytes)).value
    let anchor = encodeLightJournalAnchor(selected, fixture.oldConfig.journal.bytes).value
    let sequence = LightDeltaSequence(if maxEpoch: 2'u64 else: high(uint64))
    let frame = prepareLightDelta(image, sequence, [], [], fixture.oldConfig.journal.frame).value
    writeFile(lightChild(path, ManagedFileKind.Snapshot, epoch), lightText(image.encodedBytes))
    writeFile(lightChild(path, ManagedFileKind.Journal, epoch), lightText(anchor) & lightText(
        frame.encodedBytes))
    writeFile(path & "/CURRENT", lightText(selected.bytes))
    if maxEpoch: retireRootEpoch(path, ManagedEpoch(1))
    var owner = default(LightJournalCache)
    defer:
      resetIo()
      resetHash(0)
      if owner.opened: discard owner.close
    assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
    resetHash(0)
    if maxEpoch:
      assert prepareLightMaintenance(owner, epoch, sequence, maintenanceLimits()).error ==
          FileError.EpochExhausted and calls() == 0
      let policy = LightMaintenanceLimits(first: ManagedEpoch(high(uint64)-1), epochs: ElementLimit(
          high(uint64)))
      let plan = prepareLightMaintenance(owner, epoch, sequence, policy).value
      assert not plan.compactionNeeded and uint64(plan.retiredCount) == 1, "maximum cleanup bound cannot wrap"
      let receipt = owner.maintain(plan).value
      assert uint64(receipt.retired) == 1 and uint64(receipt.nextRetiredEpoch) == high(uint64)
      let preserve = LightMaintenanceLimits(first: epoch, epochs: ElementLimit(high(uint64)),
          keep: ElementLimit(high(uint64)))
      resetIo()
      resetHash(0)
      let idle = prepareLightMaintenance(owner, epoch, sequence, preserve).value
      assert uint64(idle.retiredCount) == 0 and not idle.compactionNeeded, "maximum keep allowance does not underflow"
      assert owner.maintain(idle).value.cleanup == FileError.None and calls() == 0 and ioCalls(
          syncIo) == 0
    else:
      let prepared = prepareLightMaintenance(owner, epoch, sequence, maintenanceLimits()).value
      let receipt = owner.maintain(prepared).value
      assert receipt.compacted and uint64(receipt.sequence) == high(uint64), "maintenance preserves maximum ordinary sequence"
      assert owner.admitRetained([], LightRetentionLimits(items: ElementLimit(4),
          valueBytes: ByteLimit(128), bytes: ByteLimit(8192), entries: ElementLimit(4))).error ==
          FileError.LimitExceeded
    let finalEpoch = owner.epoch.value
    assert owner.close == FileError.None
    assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None and uint64(
        owner.sequence.value) == uint64(sequence)
    assert owner.close == FileError.None
    retireRootEpoch(path, finalEpoch)
    retireLightJournal(path)
proc main() {.raises.} =
  ## Keep resource fixtures serial and require independent models, lifecycle and exact boundary failures before process qualification.
  let fixture = rootFixture()
  normal(fixture)
  model(fixture)
  stale(fixture)
  failures(fixture)
  readOnly()
  maxima(fixture)
try:
  main()
except:
  quit(2)
echo "PASS light maintenance: bounded threshold/range model, exact source/policy, confirmed receipts, cleanup continuation and maximum counters"
