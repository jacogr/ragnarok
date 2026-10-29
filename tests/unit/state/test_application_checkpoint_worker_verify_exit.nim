# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent child verification exits preserve exact file bytes and release locks without transferring any decoded graph.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/app/chain
import ../../../src/app/checkpoint/[worker as checkpoint_worker, writer as checkpoint_writer,
    file as checkpoint_file, codec as checkpoint_codec, identity as checkpoint_identity]
import ../../../src/state/store
import ../../../src/chain/genesis
import ../../../src/codec/bounded
import ../../../src/lib/atomic/file as atomic_file
import ../../support/[application_checkpoint_context, application_checkpoint_worker_context]
const
  Directory = "application-checkpoint-worker-verify-exit"
  FileName = Directory & "/checkpoint"
type VerificationCase = enum ## Every refused verification remains an actual completed read operation, never a publication or cancellation.
  Valid, Context, ContextBeforeBudget, MapBudget, ByteBudget, IdentityDamage
func wanted(mode: VerificationCase): ApplicationCheckpointFileError =
  ## Explicit expected reasons distinguish independent-context, resource and identity-format refusals.
  case mode
  of VerificationCase.Valid: ApplicationCheckpointFileError.None
  of VerificationCase.Context, VerificationCase.ContextBeforeBudget: ApplicationCheckpointFileError.ContextMismatch
  of VerificationCase.MapBudget, VerificationCase.ByteBudget: ApplicationCheckpointFileError.LimitExceeded
  of VerificationCase.IdentityDamage: ApplicationCheckpointFileError.IdentityFailure
proc clearFiles() =
  ## Known names retire only after children and native owners; final rmdir exposes unexpected temporary writes.
  for suffix in ["", ".lock"]:
    var path = FileName & suffix
    discard posix.unlink(path.toCString())
proc attempt(original, candidate: ApplicationChain, mode: VerificationCase) {.raises.} =
  ## No live thread/lock crosses fork; the child exits with a retained Done receipt and its exclusive writer still active.
  clearFiles()
  let actual = captureApplicationCheckpointIdentity(candidate).value
  let other = captureApplicationCheckpointIdentity(original).value
  var bytes = encodeApplicationCheckpoint(candidate, ByteLimit(100000)).value
  assert bytes.len > 238 # Prove every deliberate first-octet edit and short-ceiling subtraction.
  if mode == VerificationCase.IdentityDamage:
    bytes[0] = bytes[0] xor 1 # Producer-side malformed identity remains fixed throughout read-only verification.
  assert replaceAtomicFile(FileName, bytes, ByteLimit(100000)) == AtomicFileError.None
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var worker = default(ApplicationCheckpointWorker)
    if worker.start(FileName) != ApplicationCheckpointFileError.None: posix.exitnow(6)
    let expected = if mode in {VerificationCase.Context,
        VerificationCase.ContextBeforeBudget}: other else: actual
    var limits = genesisStoreLimits()
    if mode in {VerificationCase.ContextBeforeBudget, VerificationCase.MapBudget}:
      limits = default(StateStoreLimits) # Independent context mismatch must precede complete-map policy processing.
    let limit = if mode == VerificationCase.ByteBudget: ByteLimit(uint64(bytes.len -
        1)) else: ByteLimit(100000)
    let admitted = worker.stageVerification(expected, limits, limit)
    if admitted.error != ApplicationCheckpointWorkerError.None: posix.exitnow(7)
    if not worker.begin(admitted.value): posix.exitnow(8)
    worker.waitApplicationCheckpoint()
    let completed = worker.peek(admitted.value)
    if completed.kind != ApplicationCheckpointCompletionKind.Completed: posix.exitnow(9)
    if completed.operation != ApplicationCheckpointOperation.Verify: posix.exitnow(10)
    if completed.value.error != wanted(mode): posix.exitnow(11)
    if mode == VerificationCase.IdentityDamage and completed.value.identityError !=
        ApplicationCheckpointIdentityError.InvalidFormat:
      posix.exitnow(12) # Exact malformed identity cannot masquerade as a resource or native file refusal.
    posix.exitnow(0) # Deliberately bypass collection/join and copied-parent ARC destruction; only fixed receipts were observed.
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var ignored = 0.cint
      discard posix.waitpid(child, ignored, 0) # Every child is joined even when a parent assertion fails.
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0, "application verification child"
  assert readBoundedFile(FileName, ByteLimit(100000)).value ==
      bytes # Successful or refused verification never repairs or republishes a file.
  var reader = default(ApplicationCheckpointWriter)
  defer: discard reader.close()
  assert reader.openApplicationCheckpointWriter(FileName) == ApplicationCheckpointFileError.None
  let verified = reader.verify(actual, genesisStoreLimits(), ByteLimit(100000))
  if mode == VerificationCase.IdentityDamage:
    assert verified.error == ApplicationCheckpointFileError.IdentityFailure
    assert verified.identityError == ApplicationCheckpointIdentityError.InvalidFormat
  else:
    assert verified.error == ApplicationCheckpointFileError.None
    assert sameApplicationCheckpoint(verified.value,
        actual) # A fresh parent uses independent correct context and sufficient policy.
  assert reader.close() == ApplicationCheckpointFileError.None
proc main() {.raises.} =
  ## Header/profile/map variants cross six actual verification outcomes and unacknowledged process exits each.
  var directory = Directory
  assert posix.mkdir(directory.toCString(), Mode(0o700)) == 0
  defer:
    clearFiles()
    discard posix.rmdir(directory.toCString()) # Suite-only cleanup preserves a primary failure.
  let original = checkpointFixture()
  for variant in [CheckpointFixtureVariant.Header, CheckpointFixtureVariant.Profile,
      CheckpointFixtureVariant.State]:
    let candidate = checkpointFixture(variant)
    for mode in low(VerificationCase)..high(VerificationCase):
      attempt(original, candidate, mode) # Each child performs real bounded file decode with an exact operation/reason expectation.
  clearFiles()
  assert posix.rmdir(directory.toCString()) == 0
  echo "PASS application checkpoint verification exits: eighteen exact read-only outcomes, retained typed receipts and fresh parent lock admission"
try:
  main() # Fixture/native/child failures cannot satisfy read-only process-boundary evidence.
except:
  quit(2)
