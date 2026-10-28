# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Service-level native shutdown and real IO uncertainty preserve durable ownership and explicit restart refusals.
import std/assertions
import std/envvars
import std/syncio
import std/monotimes
import std/times
import std/posix/posix
import ../../support/app_recovery_execution
import ../../support/state_accumulation_completion_context
import ../../../src/app/services as app_services
import ../../../src/app/options as app_options
import ../../../src/app/disk_chain as app_disk_chain
import ../../../src/app/handoff as app_handoff
import ../../../src/app/block_input as app_block_input
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/chain as app_chain
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/state/store as state_store
import ../../../src/state/disk_store as state_disk_store
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../../src/storage/file_repository as storage_file_repository
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


const ChainPath = "disk-services-boundaries-chain"
const DiskPath = "disk-services-boundaries.db"
proc configured(): Options =
  ## CLI defaults supply mutation budgets while explicit controls select disk, with no listener or import fallback.
  result = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", ChainPath,
     "--state-storage", "disk", "--state-db", DiskPath], result)
proc source(owner: var Services, fixture: RecoveryExecutionFixture): PreparedFinalAccumulation {.raises.} =
  ## Actual native guest preparation binds the certificate to this newly decoded canonical map owner.
  var input = default(BlockInput)
  let id = receiveRecoveryInput(owner, input, recoveryChildBytes(fixture))
  let admitted = owner.beginPreparation(input, id)
  assert admitted.error == PreparationError.None
  owner.waitRecoveredPreparation()
  let completion = owner.collectPreparation(admitted.value)
  assert completion.kind == PreparationCompletionKind.Completed
  assert completion.value.error == BlockInputError.None
  completion.value.value
proc waitFinished(owner: var Services) =
  ## Only scalar/dispatcher work touches Services while native disk IO holds every canonical alias exclusively.
  let started = getMonoTime()
  while owner.accumulationStage != AccumulationHandoffStage.Finished:
    assert (getMonoTime()-started).inSeconds < 20
    owner.tick(0)
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Bound waits without touching protected graph aliases.
proc shutdown(fixture: RecoveryExecutionFixture) {.raises.} =
  ## Immediate close joins either queued or entered IO and leaves a strict resumable previous/successor database.
  writeFile(ChainPath, fixture.origin.text)
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(configured(), "shutdown witness")
  var path = DiskPath
  defer: discard posix.unlink(path.toCString())
  let prepared = owner.source(fixture)
  assert owner.enqueueAccumulation(prepared, completionLimits().composition) ==
      AccumulationEnqueueError.None
  owner.tick(0)
  assert owner.diskPublicationActive
  owner.close() # Never discard a native receipt or retire canonical/input graphs before joined IO.
  let receipt = owner.diskPublicationOutcome
  assert receipt.error in [DiskChainError.Uninitialized, DiskChainError.None]
  assert owner.start(configured(), "restart after joined publication")
  assert owner.chainView.retainedCount == (if receipt.error == DiskChainError.None: 2 else: 1)
  assert owner.chainView.finalizedBlock.error == GenesisError.Unavailable
  assert not owner.diskPublicationActive
  owner.close()
proc failedWrite(fixture: RecoveryExecutionFixture) {.raises.} =
  ## The parent's file/signal limits remain unchanged; all actual failures must be typed in the child.
  writeFile(ChainPath, fixture.origin.text)
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var owner = default(Services)
    if not owner.start(configured(), "kernel failure witness"): posix.exitnow(3)
    let prepared = owner.source(fixture)
    let parent = owner.stateSnapshot.value
    let previous = readFile(DiskPath)
    var selected = default(ResourceLimit)
    let ceiling = uint64(previous.len)+1
    if getLimit(fileLimit, addr selected) != 0 or ceiling > selected.maximum: posix.exitnow(4)
    if install(sizeSignal, ignore) == signalError: posix.exitnow(5)
    selected.current = ceiling
    if setLimit(fileLimit, addr selected) != 0: posix.exitnow(6)
    if owner.enqueueAccumulation(prepared, completionLimits().composition) !=
        AccumulationEnqueueError.None: posix.exitnow(7)
    owner.tick(0)
    owner.waitFinished()
    if owner.takeAccumulation().error != ApplicationChainError.DurabilityFailure: posix.exitnow(8)
    let receipt = owner.diskPublicationOutcome
    if receipt.error != DiskChainError.StoreFailure: posix.exitnow(9)
    if receipt.storeFailure.error != DiskStoreError.FileFailure: posix.exitnow(9)
    if receipt.storeFailure.fileError != FileError.IoFailure: posix.exitnow(9)
    if not sameStateSnapshot(owner.stateSnapshot.value, parent) or
        owner.preparationAvailable: posix.exitnow(10)
    let interrupted = readFile(DiskPath)
    if owner.enqueueAccumulation(prepared, completionLimits().composition) !=
        AccumulationEnqueueError.None: posix.exitnow(11)
    owner.tick(0)
    if owner.takeAccumulation().error != ApplicationChainError.DurabilityFailure or readFile(
        DiskPath) != interrupted: posix.exitnow(12)
    owner.close()
    if owner.diskPublicationOutcome.error != DiskChainError.StoreFailure: posix.exitnow(13)
    posix.exitnow(0) # Every child worker is joined; no inherited parent ARC graph is reclaimed here.
  var joined = false
  defer:
    if not joined:
      discard posix.kill(child, SIGTERM)
      var ignored = 0.cint
      discard posix.waitpid(child, ignored, 0)
  var statusCode = 0.cint
  assert posix.waitpid(child, statusCode, 0) == child
  joined = true
  assert WIFEXITED(statusCode) and WEXITSTATUS(statusCode) == 0,
      "typed disk-service failure child " & $statusCode
  var path = DiskPath
  defer: discard posix.unlink(path.toCString())
  let interrupted = readFile(DiskPath)
  var owner = default(Services)
  defer: owner.close()
  assert not owner.start(configured(), "strict partial-tail restart")
  assert readFile(DiskPath) == interrupted and owner.chainView.retainedCount == 0
proc main() {.raises.} =
  ## Child forks occur only after preceding service lifetimes have joined all disk/execution workers.
  var path = ChainPath
  defer: discard posix.unlink(path.toCString())
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let fixture = recoveryFixture(decodeOwnedReport(wire, 2).value)
  for iteration in 0..<4: shutdown(fixture)
  failedWrite(fixture)
try:
  main()
except:
  quit(2) # IO, fixture, process and native preparation failures cannot satisfy boundary evidence.
echo "PASS disk services boundaries: joined durable shutdown, typed kernel IO failure, frozen parent and strict restart"
