# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Services keeps canonical/RPC ownership frozen through native maintenance and preserves its receipt across joined shutdown.
import std/[assertions, syncio, envvars, monotimes, times]
import std/posix/posix
import ../../support/managed_storage_samples
import ../../../src/app/[services, options]
import ../../../src/app/disk/[worker as disk_worker, chain as disk_chain]
import ../../../src/app/handoff
import ../../../src/chain/[genesis, provider]
import ../../../src/state/store
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/storage/file/errors as file_errors
import ../../../src/rpc/server
proc waitFinished(owner: var Services) =
  ## Dispatcher work observes only scalar phase while the native worker owns every canonical graph alias.
  let started = getMonoTime()
  while owner.diskPublicationActive:
    owner.tick(0)
    assert (getMonoTime()-started).inSeconds < 20
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining)
proc main() {.raises.} =
  ## A real RPC listener remains paused until collection, with no canonical installation or publication receipt change.
  let path = "managed-services-maintenance"
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", getEnv(
      "RAGNAROK_APPLICATION_CHECKPOINT"),
    "--state-storage", "disk", "--state-db", path, "--state-layout", "managed",
        "--state-compact-bytes", "0",
    "--with-rpc", "--rpc-port", "24373"], options)
  var owner = default(Services)
  defer: owner.close()
  assert not owner.beginDiskMaintenance()
  assert owner.start(options, "validator")
  let before = owner.stateSnapshot.value
  assert owner.beginDiskMaintenance()
  assert owner.diskPublicationActive and owner.rpc.chainPaused
  assert owner.accumulationStage == AccumulationHandoffStage.Publishing
  assert not owner.beginDiskMaintenance()
  owner.waitFinished()
  let completed = owner.diskMaintenanceCompletion
  assert completed.kind == DiskCompletionKind.Maintained
  assert completed.maintenanceValue.error == DiskChainError.None
  assert completed.maintenanceValue.value.cleanup == FileError.None
  assert uint64(completed.maintenanceValue.value.epoch) == 2
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  assert not owner.rpc.chainPaused
  assert owner.accumulationStage == AccumulationHandoffStage.Idle
  assert owner.diskPublicationOutcome.error == DiskChainError.Uninitialized
  assert owner.beginDiskMaintenance()
  owner.stopDiskPublication() # Joined shutdown preserves an entered maintenance receipt or explicit NotExecuted.
  let joined = owner.diskMaintenanceCompletion
  assert joined.kind in {DiskCompletionKind.Maintained, DiskCompletionKind.NotExecuted}
  if joined.kind == DiskCompletionKind.Maintained: assert joined.maintenanceValue.error ==
      DiskChainError.None
  assert not owner.diskPublicationActive and not owner.rpc.chainPaused
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  owner.close()
  assert owner.diskMaintenanceCompletion.kind == joined.kind
  assert owner.start(options, "local restart")
  assert array[32, byte](owner.stateSnapshot.value.commitment.root) == array[32, byte](
      before.commitment.root)
  owner.close()
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2), ManagedEpoch(3)])
try:
  main()
except:
  quit(2)
echo "PASS managed services maintenance: RPC exclusion, stable canonical identity, exact receipts and joined restart"
