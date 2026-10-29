# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Services owns detached export lifetime, stable parent address and acknowledgement-gated joined publication receipts.
import std/[assertions, syncio, envvars, monotimes, times]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/app/checkpoint/[identity as checkpoint_identity,
    transfer as checkpoint_transfer, worker as checkpoint_worker, file as checkpoint_file]
import ../../../src/chain/genesis
import ../../../src/codec/bounded
const FileName = "application-checkpoint-services-export"
proc waitDone(owner: var Services) =
  ## Dispatcher-style scalar polling has a bounded test deadline and does not serialize or access canonical state.
  let started = getMonoTime()
  while owner.checkpointExportPhase != ApplicationCheckpointWorkerPhase.Done:
    assert (getMonoTime() - started).inSeconds < 20
    owner.tick(0)
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Yield only in native verification.
proc main() {.raises.} =
  ## Real publication survives aggregate close/restart while idle cleanup creates no fabricated duplicate receipt.
  defer:
    for suffix in ["", ".lock"]:
      var path = FileName & suffix
      discard posix.unlink(path.toCString()) # Closed Services below retire all native locks first.
  var inactive = default(Services)
  var relocated = move(inactive)
  relocated.close()
  var owner = default(Services)
  defer: owner.close()
  assert owner.startCheckpointExport(FileName) == ApplicationCheckpointFileError.Uninitialized
  assert not owner.checkpointShutdownPending
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", getEnv(
      "RAGNAROK_APPLICATION_CHECKPOINT"),
    "--state-writes", "0", "--state-write-bytes", "0"], options)
  assert owner.start(options, "checkpoint export")
  let expected = owner.checkpointIdentity.value
  assert owner.startCheckpointExport(FileName) == ApplicationCheckpointFileError.None
  var prepared = owner.prepareCheckpoint(ByteLimit(100000))
  let ticket = owner.stageCheckpointExport(prepared, ByteLimit(100000)).value
  assert owner.beginCheckpointExport(ticket)
  owner.waitDone()
  assert owner.peekCheckpointExport(ticket).value.error == ApplicationCheckpointFileError.None
  owner.close()
  owner.close()
  assert owner.checkpointShutdownPending
  assert sameApplicationCheckpoint(owner.checkpointShutdown.completion.value.value, expected)
  assert owner.start(options, "checkpoint restart")
  assert owner.startCheckpointExport(FileName) == ApplicationCheckpointFileError.Busy
  let receipt = owner.takeCheckpointShutdown()
  assert receipt.retirementError == ApplicationCheckpointFileError.None
  assert sameApplicationCheckpoint(receipt.completion.value.value, expected)
  assert owner.startCheckpointExport(FileName) == ApplicationCheckpointFileError.None
  assert not owner.beginCheckpointExport(ticket)
  var staged = owner.prepareCheckpoint(ByteLimit(100000))
  let next = owner.stageCheckpointExport(staged, ByteLimit(100000)).value
  assert owner.cancelCheckpointExport(next)
  assert owner.collectCheckpointExport(next).kind == ApplicationCheckpointCompletionKind.Cancelled
  owner.close()
  assert not owner.checkpointShutdownPending
  assert loadApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(
      100000)).error == ApplicationCheckpointFileError.None
  echo "PASS service checkpoint export: stable ownership, actual joined receipts, acknowledgement-gated restart and idle close"
try:
  main() # Fixture/native service errors cannot pass lifecycle verification.
except:
  quit(2)
