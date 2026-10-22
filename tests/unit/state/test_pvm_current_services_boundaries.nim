# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current Services refuses enabled RPC fallback, joins actual disk work and preserves kernel IO uncertainty through strict restart.
import std/[assertions, envvars, syncio, monotimes, times]
import std/posix/posix
import ../../../src/app/[services, current_block_input, current_handoff, disk_chain, disk_worker, chain]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/[store, disk_store, accumulation_current_update, accumulation_current_consensus]
import ../../../src/storage/[file_repository, managed_manifest]
import ../../../src/codec/report_owned
import ../../../src/rpc/server
import ../../support/[current_services_disk_samples, current_application_context,
  accumulation_current_chain_context, managed_storage_samples, rpc_socket]
type
  ResourceLimit {.importc: "struct rlimit", header: "<sys/resource.h>", bycopy.} = object
    ## Exact supported SDK fields constrain only the isolated writer child.
    current {.importc: "rlim_cur".}: uint64
    maximum {.importc: "rlim_max".}: uint64
  SignalHandler = proc(value: cint) {.cdecl, raises: [].} ## The signal callback never allocates or touches storage.
let fileLimit {.importc: "RLIMIT_FSIZE", header: "<sys/resource.h>".}: cint
let sizeSignal {.importc: "SIGXFSZ", header: "<signal.h>".}: cint
let signalError {.importc: "SIG_ERR", header: "<signal.h>".}: SignalHandler
proc getLimit(resource: cint, value: ptr ResourceLimit): cint {.importc: "getrlimit", cdecl,
    header: "<sys/resource.h>".}
  ## Preserve the inherited hard ceiling when lowering only the child's soft file limit.
proc setLimit(resource: cint, value: ptr ResourceLimit): cint {.importc: "setrlimit", cdecl,
    header: "<sys/resource.h>".}
  ## The native runner and its parent keep their original resource budget.
proc install(signal: cint, handler: SignalHandler): SignalHandler {.importc: "signal", cdecl,
    header: "<signal.h>".}
  ## Actual write refusal must surface as a typed error rather than signal termination.
proc ignore(value: cint) {.cdecl, raises: [].} =
  ## No allocation, output or ARC owner is reachable from this callback.
  discard
const ChainPath = "pvm-current-services-boundaries-chain"
const DiskPath = "pvm-current-services-boundaries-state"
proc waitFinished(owner: var Services) =
  ## Dispatcher/scalar polling alone is allowed until the exact disk lease has been collected.
  let started = getMonoTime()
  while owner.currentAccumulationPhase != CurrentHandoffPhase.Finished:
    assert (getMonoTime()-started).inSeconds < 20
    owner.tick(0)
    yieldCurrentDiskThread()
proc shutdown(context: CurrentChainFixture, managed, done: bool) {.raises.} =
  ## Both immediate and synchronized-Done shutdown authenticate any actual successor receipt before releasing aliases.
  var path = DiskPath
  defer:
    if managed:
      removeManagedSample(path, [ManagedEpoch(1)])
    else:
      discard posix.unlink(path.toCString()) # Exact test-owned namespace retirement follows joined shutdown.
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close()
  let options = currentDiskOptions(ChainPath, DiskPath, managed, 0)
  assert owner.start(options, "current joined shutdown")
  let parentHash = owner.chainView.bestBlock.value.blockHash
  let update = prepareCurrentServicesUpdate(owner, input, context.currentDiskChildBytes)
  let childHash = update.currentUpdateView.bestBlock.value.blockHash
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
  owner.tick(0)
  assert owner.diskPublicationActive and owner.rpc.chainPaused
  if done:
    owner.waitCurrentDiskDone() # Done still holds the lease until joined close collects the exact result.
    assert owner.diskPublicationActive and owner.rpc.chainPaused
  owner.close()
  assert not owner.diskPublicationActive and not owner.rpc.chainPaused
  let receipt = owner.diskPublicationOutcome
  assert receipt.error in {DiskChainError.Uninitialized, DiskChainError.None}
  if done: assert receipt.error == DiskChainError.None # A completed actual IO job cannot become queued-not-executed.
  assert owner.start(options, "strict restart after joined current work")
  let expectedHash = if receipt.error == DiskChainError.None: childHash else: parentHash
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](expectedHash)
  if receipt.error == DiskChainError.None:
    equalCurrentDiskMap(owner.stateSnapshot.value, context.source.currentConsensusState.value)
  else:
    equalCurrentDiskMap(owner.stateSnapshot.value, context.parent.value.stateSnapshot)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  owner.close()
proc refusedRpc(context: CurrentChainFixture) {.raises.} =
  ## An enabled listener closed before staging grants neither disk IO nor canonical-only fallback.
  var path = DiskPath
  defer: discard posix.unlink(path.toCString())
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close()
  let reserved = reservation()
  discard posix.close(reserved.fd)
  let options = currentDiskOptions(ChainPath, DiskPath, false, reserved.port)
  assert owner.start(options, "enabled RPC refusal")
  let parent = owner.stateSnapshot.value
  let previous = readFile(DiskPath)
  let update = prepareCurrentServicesUpdate(owner, input, context.currentDiskChildBytes)
  owner.rpc.close()
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
  owner.tick(0)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished
  assert owner.takeCurrentAccumulation().error == CurrentHandoffError.RpcRefused
  assert owner.currentDiskPublicationAdmissionError == DiskWorkerError.Uninitialized
  assert owner.currentDiskPreparationOutcome.error == DiskChainError.Uninitialized
  assert owner.diskPublicationOutcome.error == DiskChainError.Uninitialized
  assert not owner.diskPublicationActive and not owner.rpc.chainPaused
  assert sameStateSnapshot(owner.stateSnapshot.value, parent)
  assert readFile(DiskPath) == previous
  owner.close()
  assert owner.start(options, "strict unchanged parent restart")
  equalCurrentDiskMap(owner.stateSnapshot.value, context.parent.value.stateSnapshot)
  owner.close()
proc failedWrite(context: CurrentChainFixture) {.raises.} =
  ## Fork only after all earlier worker owners joined; actual partial journal failure must remain observable and frozen.
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var input = default(CurrentBlockInput)
    var owner = default(Services)
    let options = currentDiskOptions(ChainPath, DiskPath, false, 0)
    if not owner.start(options, "current kernel failure"): posix.exitnow(3)
    let parent = owner.stateSnapshot.value
    let update = prepareCurrentServicesUpdate(owner, input, context.currentDiskChildBytes)
    let previous = readFile(DiskPath)
    var selected = default(ResourceLimit)
    let ceiling = uint64(previous.len)+1
    if getLimit(fileLimit, addr selected) != 0 or ceiling > selected.maximum: posix.exitnow(4)
    if install(sizeSignal, ignore) == signalError: posix.exitnow(5)
    selected.current = ceiling
    if setLimit(fileLimit, addr selected) != 0: posix.exitnow(6)
    if owner.enqueueCurrentAccumulation(update) != CurrentHandoffAdmission.None: posix.exitnow(7)
    owner.tick(0)
    owner.waitFinished()
    if owner.takeCurrentAccumulation().error != CurrentHandoffError.DurabilityRefused: posix.exitnow(8)
    let receipt = owner.diskPublicationOutcome
    if receipt.error != DiskChainError.StoreFailure: posix.exitnow(9)
    if receipt.storeFailure.error != DiskStoreError.FileFailure: posix.exitnow(10)
    if receipt.storeFailure.fileError != FileError.IoFailure: posix.exitnow(11)
    if not sameStateSnapshot(owner.stateSnapshot.value, parent): posix.exitnow(12)
    if owner.preparationAvailable or owner.stateProofAvailable: posix.exitnow(13)
    let interrupted = readFile(DiskPath)
    if owner.enqueueCurrentAccumulation(update) !=
        CurrentHandoffAdmission.Unavailable: posix.exitnow(14)
    owner.tick(0)
    if readFile(DiskPath) != interrupted: posix.exitnow(15)
    owner.close()
    if owner.diskPublicationOutcome.error != DiskChainError.StoreFailure: posix.exitnow(16)
    posix.exitnow(0) # Every native borrower is joined before bypassing inherited parent ARC reclamation.
  var joined = false
  defer:
    if not joined:
      discard posix.kill(child, SIGTERM)
      var ignored = 0.cint
      discard posix.waitpid(child, ignored, 0) # No exceptional path abandons a writer child.
  var statusCode = 0.cint
  assert posix.waitpid(child, statusCode, 0) == child
  joined = true
  assert WIFEXITED(statusCode) and WEXITSTATUS(statusCode) == 0,
      "typed current Services IO child " & $statusCode
  var path = DiskPath
  defer: discard posix.unlink(path.toCString())
  let interrupted = readFile(DiskPath)
  assert interrupted.len > 0
  var owner = default(Services)
  defer: owner.close()
  assert not owner.start(currentDiskOptions(ChainPath, DiskPath, false, 0), "strict partial-tail restart")
  assert readFile(DiskPath) == interrupted and owner.chainView.retainedCount == 0
proc main() {.raises.} =
  ## Independent fixture decoding precedes sequential Service lifetimes and the isolated resource-failure child.
  var path = ChainPath
  defer: discard posix.unlink(path.toCString())
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, available = true)
  writeFile(ChainPath, context.currentApplicationText)
  shutdown(context, false, false)
  shutdown(context, false, true)
  shutdown(context, true, false)
  shutdown(context, true, true)
  refusedRpc(context)
  failedWrite(context)
try:
  main()
except:
  quit(2) # Resource, RPC, execution and restart failures cannot count as successful boundary evidence.
echo "PVM current Services boundaries passed"
