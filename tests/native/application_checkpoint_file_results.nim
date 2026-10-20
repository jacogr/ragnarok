# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Invalid file outcomes must fail the exact same checked accessors as genuine publication and recovery.
import std/[assertions, cmdline, syncio]
import std/posix/posix
import ../../src/app/[chain, checkpoint_file, checkpoint_identity]
import ../../src/state/store
import ../../src/chain/genesis
import ../../src/codec/bounded
import ../../src/lib/atomic_file
import ../support/application_checkpoint_context
proc extractIdentity(outcome: ApplicationCheckpointFileResult[ApplicationCheckpointIdentity]) =
  ## Publication grants context only after durable complete success.
  discard outcome.value
proc extractStore(outcome: ApplicationCheckpointFileResult[StateStore]) =
  ## Failed files never grant a partial complete-map owner.
  discard outcome.value
proc inspectIdentity(outcome: ApplicationCheckpointFileResult[StateStore]) =
  ## Only matching identity failures expose their cause.
  discard outcome.identityError
proc inspectCheckpoint(outcome: ApplicationCheckpointFileResult[StateStore]) =
  ## Only matching map failures expose their cause.
  discard outcome.checkpointError
proc main() {.raises.} =
  ## Independent fixture context and a real file provide genuine controls; misuse modes need no fixture.
  let mode = paramStr(1)
  let absent = default(ApplicationCheckpointIdentity)
  let refused = loadApplicationCheckpoint("missing-file-context", absent, genesisStoreLimits(),
      ByteLimit(1000))
  if mode == "default-save":
    let empty = default(ApplicationCheckpointFileResult[ApplicationCheckpointIdentity])
    extractIdentity(empty) # No default publication receipt exists.
  elif mode == "default-load":
    let empty = default(ApplicationCheckpointFileResult[StateStore])
    extractStore(empty) # Default restoration has no map.
  elif mode == "failed-load":
    extractStore(refused) # Missing independent context refuses before any file read.
  elif mode == "identity-reason":
    let empty = default(ApplicationCheckpointFileResult[StateStore])
    inspectIdentity(empty) # Default has no selected identity cause.
  elif mode == "checkpoint-reason":
    inspectCheckpoint(refused) # Identity refusal is not a complete-map failure.
  else:
    assert mode == "positive"
    var path = "build/application-checkpoint-file-guard"
    defer: discard posix.unlink(path.toCString())
    let owner = checkpointFixture()
    let expected = captureApplicationCheckpointIdentity(owner).value
    extractIdentity(saveApplicationCheckpoint(path, owner, ByteLimit(100000)))
    extractStore(loadApplicationCheckpoint(path, expected, genesisStoreLimits(), ByteLimit(100000)))
    inspectIdentity(refused)
    let prefix = encodeApplicationCheckpointIdentity(expected, ByteLimit(100000)).value
    assert replaceAtomicFile(path, prefix, ByteLimit(100000)) == AtomicFileError.None
    inspectCheckpoint(loadApplicationCheckpoint(path, expected, genesisStoreLimits(), ByteLimit(
        100000))) # A genuine truncated-map refusal passes this same selected-reason helper.
try:
  main() # Setup errors remain distinct from runtime contract exits.
except:
  quit(2)
