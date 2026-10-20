# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A live worker address, unjoined native lifetime and unselected result alternatives enforce runtime contracts.
import std/[assertions, cmdline, syncio]
import std/posix/posix
import ../../src/app/[checkpoint_worker, checkpoint_file, checkpoint_identity]
import ../../src/codec/bounded
import ../support/application_checkpoint_worker_context
proc extractAdmission(admission: ApplicationCheckpointAdmission) =
  ## Only actual admitted ownership grants a ticket.
  discard admission.value
proc extractCompletion(completion: ApplicationCheckpointCompletion) =
  ## Only native operation completion carries a file outcome.
  discard completion.value
proc forgotten() {.raises.} =
  ## Start a genuine thread before witnessing required explicit joined destruction.
  var worker = default(ApplicationCheckpointWorker)
  assert worker.start("build/application-checkpoint-worker-unclosed") ==
      ApplicationCheckpointFileError.None
proc main() {.raises.} =
  ## Genuine native publication and inactive relocation exercise the same selected access and lifecycle paths.
  let mode = paramStr(1)
  if mode == "unclosed":
    forgotten() # A live thread cannot silently outlive its owner.
  elif mode == "moved":
    var worker = default(ApplicationCheckpointWorker)
    assert worker.start("build/application-checkpoint-worker-moved") ==
        ApplicationCheckpointFileError.None
    var transferred = move(worker)
    discard transferred.close() # Actual lowering must invoke the checked stable-address move hook.
  elif mode == "admission":
    let absent = default(ApplicationCheckpointAdmission)
    extractAdmission(absent) # No default ticket authority exists.
  elif mode == "completion":
    let absent = default(ApplicationCheckpointCompletion)
    extractCompletion(absent) # Default completion has no publication receipt.
  else:
    assert mode == "positive"
    var path = "build/application-checkpoint-worker-guard"
    var lockPath = path & ".lock"
    defer:
      discard posix.unlink(path.toCString())
      discard posix.unlink(lockPath.toCString()) # Test-only cleanup follows native joined shutdown.
    var inactive = default(ApplicationCheckpointWorker)
    var relocated = move(inactive)
    discard relocated.close()
    var worker = default(ApplicationCheckpointWorker)
    defer: discard worker.close()
    assert worker.start(path) == ApplicationCheckpointFileError.None
    var source = detachedApplicationCheckpoint()
    let admitted = worker.stage(source, ByteLimit(100000))
    extractAdmission(admitted)
    assert worker.begin(admitted.value)
    worker.waitApplicationCheckpoint()
    let completed = worker.collect(admitted.value)
    extractCompletion(completed)
    assert completed.value.error == ApplicationCheckpointFileError.None
    assert completed.value.value.ready
    assert worker.close().retirementError == ApplicationCheckpointFileError.None
try:
  main() # Setup exceptions do not count as expected runtime contract failures.
except:
  quit(2)
