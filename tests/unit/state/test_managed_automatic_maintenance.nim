# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine native execution confirms managed publication before automatic maintenance, preserving full maps and restart history.
import std/[assertions, syncio, envvars, monotimes, times]
import std/posix/posix
import ../../support/[application_recovery_execution, accumulation_completion_context, managed_storage_samples]
import ../../../src/app/[services, options, disk_chain, disk_worker, handoff, block_input,
    preparation_worker, chain]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/[store, accumulation_finalization, accumulation_publication]
import ../../../src/storage/managed_manifest
import ../../../src/codec/[report_owned, state_layout]
proc source(owner: var Services, fixture: RecoveryExecutionFixture): PreparedFinalAccumulation {.raises.} =
  ## Actual execution creates a certificate bound to this Services owner's independently restored parent map.
  var input = default(BlockInput)
  let identity = receiveRecoveryInput(owner, input, recoveryChildBytes(fixture))
  let admitted = owner.beginPreparation(input, identity)
  assert admitted.error == PreparationError.None
  owner.waitRecoveredPreparation()
  let completed = owner.collectPreparation(admitted.value)
  assert completed.kind == PreparationCompletionKind.Completed and completed.value.error ==
      BlockInputError.None
  completed.value.value
proc configured(chainPath, diskPath: string, threshold: string): Options =
  ## Explicit zero and a one-byte soft threshold exercise disabled and enabled scheduling without widening limits.
  result = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", chainPath, "--state-storage", "disk",
    "--state-db", diskPath, "--state-layout", "managed", "--state-compact-bytes", threshold], result)
proc cycle(fixture: RecoveryExecutionFixture, automatic: bool) {.raises.} =
  ## Automatic reclamation holds the completed adoption behind the same publication backpressure until every lease ends.
  var chainPath = "managed-auto-chain-" & $(if automatic: 1 else: 0)
  let path = "managed-auto-store-" & $(if automatic: 1 else: 0)
  writeFile(chainPath, fixture.origin.text)
  var owner = default(Services)
  defer:
    owner.close()
    discard posix.unlink(chainPath.toCString())
  assert owner.start(configured(chainPath, path, if automatic: "1" else: "0"), "execution")
  let prepared = owner.source(fixture)
  let canonical = initApplicationChain(owner.chainView).value
  let expected = canonical.prepareAccumulation(prepared, completionLimits().composition).value
  assert owner.enqueueAccumulation(prepared, completionLimits().composition) ==
      AccumulationEnqueueError.None
  let started = getMonoTime()
  while owner.accumulationStage != AccumulationHandoffStage.Finished or owner.diskPublicationActive:
    owner.tick(0)
    if owner.diskPublicationActive:
      assert owner.accumulationStage == AccumulationHandoffStage.Publishing # Never expose a graph-bearing acknowledgement during maintenance.
    assert (getMonoTime()-started).inSeconds < 30
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Never inspect any canonical or prepared alias while either native IO lease is active.
  assert owner.takeAccumulation().error == ApplicationChainError.None
  assert owner.diskPublicationOutcome.error == DiskChainError.None
  assert uint64(owner.diskPublicationOutcome.value) == 2
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](
      expected.child.blockHash)
  let actual = owner.stateSnapshot.value
  for index in 0..<expected.stateSnapshot.commitment.entries:
    let key = expected.stateSnapshot.keyAt(StateEntryIndex(index)).value
    assert actual.lookup(key).value.bytes == expected.stateSnapshot.lookup(key).value.bytes
  if automatic:
    let maintenance = owner.diskMaintenanceCompletion
    assert maintenance.kind == DiskCompletionKind.Maintained and
        maintenance.maintenanceValue.error == DiskChainError.None
    assert uint64(maintenance.maintenanceValue.value.generation) == 2
    assert uint64(maintenance.maintenanceValue.value.epoch) == 2
  else:
    assert owner.diskMaintenanceCompletion.kind == DiskCompletionKind.Uninitialized
  owner.close()
  assert owner.start(configured(chainPath, path, "1"), "local restart")
  if automatic:
    assert owner.startupDiskMaintenanceOutcome.error == DiskChainError.Uninitialized
  else:
    assert owner.startupDiskMaintenanceOutcome.error == DiskChainError.None
    assert uint64(owner.startupDiskMaintenanceOutcome.value.epoch) == 2
    assert uint64(owner.startupDiskMaintenanceOutcome.value.generation) == 2
  assert owner.chainView.retainedCount == 2 and owner.chainView.finalizedBlock.error ==
      GenesisError.Unavailable
  assert array[32, byte](owner.stateSnapshot.value.commitment.root) == array[32, byte](
      expected.stateSnapshot.commitment.root)
  for iteration in 0..<8:
    owner.tick(0)
    assert not owner.diskPublicationActive # A header-only journal cannot cause an endless compaction loop.
  owner.close()
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
proc main() {.raises.} =
  ## Published report inputs feed existing signed two-guest execution fixtures; no production validation is bypassed.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let fixture = recoveryFixture(decodeOwnedReport(bytes, 2).value)
  cycle(fixture, true)
  cycle(fixture, false)
try:
  main()
except:
  quit(2)
echo "PASS managed automatic maintenance: genuine execution, confirmed publication, full-map parity, disabled policy and startup reclaim"
