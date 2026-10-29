# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real child-only kernel refusals cannot splice application metadata and complete-map bytes or lose the old envelope.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/app/chain
import ../../../src/app/checkpoint/[writer as checkpoint_writer, worker as checkpoint_worker,
    file as checkpoint_file, transfer as checkpoint_transfer, codec as checkpoint_codec,
    identity as checkpoint_identity]
import ../../../src/chain/genesis
import ../../../src/codec/bounded
import ../../../src/lib/atomic/file as atomic_file
import ../../support/[application_checkpoint_context, application_checkpoint_worker_context,
    file_size_ceiling]
const
  Directory = "application-checkpoint-worker-write-failure"
  FileName = Directory & "/checkpoint"
proc clearFiles() =
  ## Only known suite-owned files are removed after every child and native owner retires.
  for suffix in ["", ".lock"]:
    var path = FileName & suffix
    discard posix.unlink(path.toCString()) # Final rmdir deliberately leaves unexpected operation temporaries observable.
proc attempt(original, candidate: ApplicationChain, ceiling: uint64, succeeds,
    collect: bool) {.raises.} =
  ## Soft limits differ from valid producer byte policy, so expected refusal must come from actual native writing.
  clearFiles()
  let expectedOld = captureApplicationCheckpointIdentity(original).value
  let expectedNew = captureApplicationCheckpointIdentity(candidate).value
  let oldBytes = encodeApplicationCheckpoint(original, ByteLimit(100000)).value
  let newBytes = encodeApplicationCheckpoint(candidate, ByteLimit(100000)).value
  assert saveApplicationCheckpoint(FileName, original, ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.None
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    let restricted = restrictFileSize(ceiling)
    if restricted != 0: posix.exitnow(restricted) # Resource/signal setup cannot satisfy the expected typed write refusal.
    var worker = default(ApplicationCheckpointWorker)
    if worker.start(FileName) != ApplicationCheckpointFileError.None: posix.exitnow(6)
    var prepared = prepareApplicationCheckpoint(candidate, ByteLimit(100000))
    let ticket = worker.stage(prepared, ByteLimit(100000)).value
    if not worker.begin(ticket): posix.exitnow(7)
    worker.waitApplicationCheckpoint()
    var completed = default(ApplicationCheckpointCompletion)
    if collect:
      completed = worker.collect(ticket) # Explicit acknowledgement must preserve the actual native refusal too.
      if worker.close().retirementError != ApplicationCheckpointFileError.None: posix.exitnow(8)
    else:
      let shutdown = worker.close() # Joined shutdown preserves the same operation outcome without prior acknowledgement.
      if shutdown.retirementError != ApplicationCheckpointFileError.None: posix.exitnow(8)
      completed = shutdown.completion
    if completed.kind != ApplicationCheckpointCompletionKind.Completed: posix.exitnow(9)
    let wanted = if succeeds: ApplicationCheckpointFileError.None else: ApplicationCheckpointFileError.IoFailure
    if completed.value.error != wanted: posix.exitnow(
        10) # Native refusal cannot become Cancelled, Interrupted or producer LimitExceeded.
    let expected = if succeeds: expectedNew else: expectedOld
    var reader = default(ApplicationCheckpointWriter)
    if reader.openApplicationCheckpointWriter(FileName) !=
        ApplicationCheckpointFileError.None: posix.exitnow(11)
    if reader.load(expected, genesisStoreLimits(), ByteLimit(100000)).error !=
        ApplicationCheckpointFileError.None: posix.exitnow(12)
    if reader.close() != ApplicationCheckpointFileError.None: posix.exitnow(13)
    posix.exitnow(0) # Do not destroy copied parent ARC graphs; this is not cross-process allocator evidence.
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var ignored = 0.cint
      discard posix.waitpid(child, ignored, 0) # Failed parent assertions never abandon a child.
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0, "application checkpoint kernel refusal child"
  let wantedBytes = if succeeds: newBytes else: oldBytes
  let expected = if succeeds: expectedNew else: expectedOld
  assert readBoundedFile(FileName, ByteLimit(100000)).value ==
      wantedBytes # Header/profile/root and complete map are atomically the same old or new envelope.
  assert loadApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(
      100000)).error == ApplicationCheckpointFileError.None
  let wrong = if succeeds: expectedOld else: expectedNew
  assert loadApplicationCheckpoint(FileName, wrong, genesisStoreLimits(), ByteLimit(
      100000)).error == ApplicationCheckpointFileError.ContextMismatch
proc main() {.raises.} =
  ## Header-only, profile-only and map-only changes all cross zero/partial kernel failures and exact/ample successes.
  var directory = Directory
  assert posix.mkdir(directory.toCString(), Mode(0o700)) == 0
  defer:
    clearFiles()
    discard posix.rmdir(directory.toCString()) # Preserve a primary failure while attempting suite-only cleanup.
  let original = checkpointFixture()
  for variant in [CheckpointFixtureVariant.Header, CheckpointFixtureVariant.Profile,
      CheckpointFixtureVariant.State]:
    let candidate = checkpointFixture(variant)
    let size = uint64(encodeApplicationCheckpoint(candidate, ByteLimit(100000)).value.len)
    for collect in [false, true]:
      for ceiling in [0'u64, 1'u64, size - 1]:
        attempt(original, candidate, ceiling, false,
            collect) # Actual worker failure must survive both collection and joined shutdown.
      for ceiling in [size, size + 1]:
        attempt(original, candidate, ceiling, true,
            collect) # Exact/ample controls use the identical worker and acknowledgement paths.
  clearFiles()
  assert posix.rmdir(directory.toCString()) == 0 # No failed operation may leave a temporary sibling behind.
  echo "PASS application checkpoint worker write failures: eighteen kernel refusals, twelve controls and exact collected/joined receipts"
try:
  main() # Fixture/native setup or child failures must remain suite failures.
except:
  quit(2)
