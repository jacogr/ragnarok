# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Known pre-dispatch and durable-Done process exit boundaries preserve exact envelopes and release native locks.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/app/[chain, checkpoint_worker, checkpoint_writer, checkpoint_file,
    checkpoint_codec, checkpoint_transfer, checkpoint_identity]
import ../../../src/codec/bounded
import ../../../src/chain/genesis
import ../../../src/lib/atomic_file
import ../../support/[application_checkpoint_context, application_checkpoint_worker_context]
const
  Directory = "application-checkpoint-worker-crash"
  FileName = Directory & "/checkpoint"
type ExitBoundary = enum ## These observed boundaries make no claim about unobserved mid-write interruption.
  Staged, Cancelled, Durable
proc clearFiles() =
  ## Only known names are removed after native owners and children retire; final rmdir detects orphan temporaries.
  for suffix in ["", ".lock"]:
    var path = FileName & suffix
    discard posix.unlink(path.toCString())
proc attempt(original, candidate: ApplicationChain, boundary: ExitBoundary) {.raises.} =
  ## A child exits without collection or joined close; the OS must release its private lock for independent parent recovery.
  clearFiles()
  let originalIdentity = captureApplicationCheckpointIdentity(original).value
  let candidateIdentity = captureApplicationCheckpointIdentity(candidate).value
  let oldBytes = encodeApplicationCheckpoint(original, ByteLimit(100000)).value
  let newBytes = encodeApplicationCheckpoint(candidate, ByteLimit(100000)).value
  assert saveApplicationCheckpoint(FileName, original, ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.None
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var worker = default(ApplicationCheckpointWorker)
    if worker.start(FileName) != ApplicationCheckpointFileError.None: posix.exitnow(6)
    var source = prepareApplicationCheckpoint(candidate, ByteLimit(100000))
    let admitted = worker.stage(source, ByteLimit(100000))
    if admitted.error != ApplicationCheckpointWorkerError.None: posix.exitnow(7)
    let ticket = admitted.value
    case boundary
    of ExitBoundary.Staged:
      if worker.phase != ApplicationCheckpointWorkerPhase.Staged: posix.exitnow(8)
    of ExitBoundary.Cancelled:
      if not worker.cancel(ticket): posix.exitnow(9)
      if worker.peek(ticket).kind != ApplicationCheckpointCompletionKind.Cancelled: posix.exitnow(10)
    of ExitBoundary.Durable:
      if not worker.begin(ticket): posix.exitnow(11)
      worker.waitApplicationCheckpoint()
      let completed = worker.peek(ticket)
      if completed.kind != ApplicationCheckpointCompletionKind.Completed: posix.exitnow(12)
      if completed.value.error != ApplicationCheckpointFileError.None: posix.exitnow(13)
      if not sameApplicationCheckpoint(completed.value.value, candidateIdentity): posix.exitnow(14)
    posix.exitnow(0) # Deliberately bypass collection, joined shutdown and copied parent ARC destruction.
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var ignored = 0.cint
      discard posix.waitpid(child, ignored, 0) # Parent assertions never leave a child or live worker process behind.
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0, "application worker process boundary"
  let durable = boundary == ExitBoundary.Durable
  let expected = if durable: candidateIdentity else: originalIdentity
  let bytes = if durable: newBytes else: oldBytes
  assert readBoundedFile(FileName, ByteLimit(100000)).value == bytes
  var reader = default(ApplicationCheckpointWriter)
  defer: discard reader.close()
  assert reader.openApplicationCheckpointWriter(FileName) == ApplicationCheckpointFileError.None
  assert reader.load(expected, genesisStoreLimits(), ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.None
  let other = if durable: originalIdentity else: candidateIdentity
  assert reader.load(other, genesisStoreLimits(), ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.ContextMismatch
  assert reader.close() == ApplicationCheckpointFileError.None
proc main() {.raises.} =
  ## Header, profile and map changes cross each known exit boundary without automatic adoption or self-authenticated recovery.
  var directory = Directory
  assert posix.mkdir(directory.toCString(), Mode(0o700)) == 0
  defer:
    clearFiles()
    discard posix.rmdir(directory.toCString()) # Best-effort suite-only cleanup preserves a primary failure.
  let original = checkpointFixture()
  for variant in [CheckpointFixtureVariant.Header, CheckpointFixtureVariant.Profile,
      CheckpointFixtureVariant.State]:
    let candidate = checkpointFixture(variant)
    for boundary in [ExitBoundary.Staged, ExitBoundary.Cancelled, ExitBoundary.Durable]:
      attempt(original, candidate, boundary) # Parent recovery uses independent expected context at every boundary.
  clearFiles()
  assert posix.rmdir(directory.toCString()) == 0
  echo "PASS application checkpoint process exits: staged, cancelled and durable unacknowledged envelopes recover exactly"
try:
  main() # Fixture/child/native errors cannot count as a successful process recovery witness.
except:
  quit(2)
