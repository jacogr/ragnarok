# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real child-only kernel refusals cannot splice application metadata and complete-map bytes or lose the old envelope.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/app/[chain, checkpoint_writer, checkpoint_file, checkpoint_transfer,
    checkpoint_codec, checkpoint_identity]
import ../../../src/chain/genesis
import ../../../src/codec/bounded
import ../../../src/lib/atomic_file
import ../../support/[application_checkpoint_context, file_size_ceiling]
const
  Directory = "application-checkpoint-write-failure"
  FileName = Directory & "/checkpoint"
proc clearFiles() =
  ## Only known suite-owned files are removed after every child and native owner retires.
  for suffix in ["", ".lock"]:
    var path = FileName & suffix
    discard posix.unlink(path.toCString()) # Final rmdir deliberately leaves unexpected operation temporaries observable.
proc attempt(original, candidate: ApplicationChain, ceiling: uint64, succeeds: bool) {.raises.} =
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
    var writer = default(ApplicationCheckpointWriter)
    if writer.openApplicationCheckpointWriter(FileName) !=
        ApplicationCheckpointFileError.None: posix.exitnow(6)
    var prepared = prepareApplicationCheckpoint(candidate, ByteLimit(100000))
    let outcome = writer.save(prepared, ByteLimit(100000))
    let wanted = if succeeds: ApplicationCheckpointFileError.None else: ApplicationCheckpointFileError.IoFailure
    if outcome.error != wanted: posix.exitnow(7) # A producer limit or uninitialized buffer is not a real kernel refusal.
    let expected = if succeeds: expectedNew else: expectedOld
    if writer.load(expected, genesisStoreLimits(), ByteLimit(100000)).error !=
        ApplicationCheckpointFileError.None: posix.exitnow(8)
    if writer.close() != ApplicationCheckpointFileError.None: posix.exitnow(9)
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
    for ceiling in [0'u64, 1'u64, size - 1]:
      attempt(original, candidate, ceiling, false) # Each failure must preserve the complete exact old application envelope.
    for ceiling in [size, size + 1]:
      attempt(original, candidate, ceiling, true) # The identical implementation succeeds at exact and ample native file size.
  clearFiles()
  assert posix.rmdir(directory.toCString()) == 0 # No failed operation may leave a temporary sibling behind.
  echo "PASS application checkpoint write failures: nine kernel refusals, six exact controls and whole-envelope rollback"
try:
  main() # Fixture/native setup or child failures must remain suite failures.
except:
  quit(2)
