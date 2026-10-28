# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual exclusive-create refusal and kernel short writes preserve confirmed heads and report maintenance failure separately.
import std/assertions
import std/syncio
import std/envvars
import std/monotimes
import std/times
import std/posix/posix
import ../../support/app_recovery_execution
import ../../support/state_accumulation_completion_context
import ../../support/app_managed_storage_samples
import ../../../src/app/services as app_services
import ../../../src/app/options as app_options
import ../../../src/app/disk_chain as app_disk_chain
import ../../../src/app/disk_worker as app_disk_worker
import ../../../src/app/handoff as app_handoff
import ../../../src/app/block_input as app_block_input
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/chain as app_chain
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/report_owned as codec_report_owned
type
  ResourceLimit {.importc: "struct rlimit", header: "<sys/resource.h>", bycopy.} = object
    ## Exact supported 64-bit SDK fields constrain only the forked writer.
    current {.importc: "rlim_cur".}: uint64
    maximum {.importc: "rlim_max".}: uint64
  SignalHandler = proc(value: cint) {.cdecl, raises: [].} ## Nonallocating callback keeps kernel refusal observable.
let fileLimit {.importc: "RLIMIT_FSIZE", header: "<sys/resource.h>".}: cint
let sizeSignal {.importc: "SIGXFSZ", header: "<signal.h>".}: cint
let signalError {.importc: "SIG_ERR", header: "<signal.h>".}: SignalHandler
proc getLimit(resource: cint, value: ptr ResourceLimit): cint {.importc: "getrlimit", cdecl,
    header: "<sys/resource.h>".}
  ## Inspect the inherited hard ceiling before selecting a smaller soft limit.
proc setLimit(resource: cint, value: ptr ResourceLimit): cint {.importc: "setrlimit", cdecl,
    header: "<sys/resource.h>".}
  ## Change only the isolated child, never the native runner's resource budget.
proc install(signal: cint, handler: SignalHandler): SignalHandler {.importc: "signal", cdecl,
    header: "<signal.h>".}
  ## Keep SIGXFSZ as a typed write error rather than accepting signal termination as evidence.
proc ignore(value: cint) {.cdecl, raises: [].} =
  ## Signal handling performs no allocation, output or storage operation.
  discard

proc configured(chainPath, path, threshold: string): Options =
  ## Threshold policy is explicit and never changes the admitted local chain identity.
  result = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", chainPath, "--state-storage", "disk",
    "--state-db", path, "--state-layout", "managed", "--state-compact-bytes", threshold], result)
proc waitFinished(owner: var Services) =
  ## Only scalar phase and dispatcher ticks run during native publication or maintenance.
  let started = getMonoTime()
  while owner.diskPublicationActive or owner.accumulationStage in {AccumulationHandoffStage.Pending,
      AccumulationHandoffStage.Publishing}:
    owner.tick(0)
    assert (getMonoTime()-started).inSeconds < 30
    var request = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(request, remaining)
proc collision(fixture: RecoveryExecutionFixture) {.raises.} =
  ## A real CURRENT.next O_EXCL refusal occurs after the genuine child's journal publication is already confirmed.
  var chainPath = "managed-failure-chain"
  let path = "managed-failure-collision"
  writeFile(chainPath, fixture.origin.text)
  var owner = default(Services)
  defer:
    owner.close()
    discard posix.unlink(chainPath.toCString())
  assert owner.start(configured(chainPath, path, "1"), "collision witness")
  let original = readFile(path & "/CURRENT")
  var input = default(BlockInput)
  let id = receiveRecoveryInput(owner, input, recoveryChildBytes(fixture))
  let admitted = owner.beginPreparation(input, id)
  assert admitted.error == PreparationError.None
  owner.waitRecoveredPreparation()
  let prepared = owner.collectPreparation(admitted.value).value.value
  writeFile(path & "/CURRENT.next", "interrupted") # Test-owned namespace fault; no production injection hook is added.
  assert owner.enqueueAccumulation(prepared, completionLimits().composition) ==
      AccumulationEnqueueError.None
  owner.waitFinished()
  assert owner.takeAccumulation().error == ApplicationChainError.None
  assert owner.diskPublicationOutcome.error == DiskChainError.None and uint64(
      owner.diskPublicationOutcome.value) == 2
  assert owner.diskMaintenanceFailed
  let failure = owner.diskMaintenanceCompletion.maintenanceValue
  assert failure.error == DiskChainError.MaintenanceFailure and
      failure.maintenanceFailure.fileError == FileError.AlreadyExists
  let confirmed = owner.chainView.bestBlock.value
  assert not owner.beginDiskMaintenance() # An uncertain maintenance owner cannot attempt more mutations.
  assert readFile(path & "/CURRENT") == original
  owner.close()
  assert owner.diskMaintenanceFailed
  assert owner.start(configured(chainPath, path, "0"), "explicit no-maintenance restart")
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](
      confirmed.blockHash)
  assert owner.chainView.retainedCount == 2
  owner.close()
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
proc kernelFailure() {.raises.} =
  ## Fork before starting any Services worker; only the child's native snapshot writes receive the zero file ceiling.
  let chainPath = getEnv("RAGNAROK_APPLICATION_CHECKPOINT")
  let path = "managed-failure-kernel"
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var owner = default(Services)
    if not owner.start(configured(chainPath, path, "0"), "kernel writer"): posix.exitnow(3)
    var policy = default(ResourceLimit)
    if getLimit(fileLimit, addr policy) != 0: posix.exitnow(4)
    if install(sizeSignal, ignore) == signalError: posix.exitnow(5)
    policy.current = 0
    if setLimit(fileLimit, addr policy) != 0: posix.exitnow(6)
    if not owner.beginDiskMaintenance(): posix.exitnow(7)
    owner.waitFinished()
    if not owner.diskMaintenanceFailed: posix.exitnow(8)
    let failed = owner.diskMaintenanceCompletion.maintenanceValue
    if failed.error != DiskChainError.MaintenanceFailure or failed.maintenanceFailure.fileError !=
        FileError.IoFailure:
      posix.exitnow(9)
    posix.exitnow(0) # The kernel, rather than close/destruction, must retire all worker descriptors and the stable lock.
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0
  assert readFile(path & "/snapshot-0000000000000002.bin").len == 0
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(configured(chainPath, path, "0"), "strict old-head resume")
  assert owner.chainView.retainedCount == 1 and not owner.diskMaintenanceFailed
  owner.close()
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
proc main() {.raises.} =
  ## Genuine signed execution covers post-publication failure; a separate real kernel limit covers partial staging.
  kernelFailure() # Fork before any Services worker or genuine guest fixture has started in the parent.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  collision(recoveryFixture(decodeOwnedReport(bytes, 2).value))
try:
  main()
except:
  quit(2)
echo "PASS managed maintenance failures: confirmed child preservation, actual IO reasons, poisoned mutation and abrupt restart"
