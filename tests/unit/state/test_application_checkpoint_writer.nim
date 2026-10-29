# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_checkpoint_writer_arc_release"}

## Cooperative whole-envelope ownership preserves path identity, contention and precise recovery across close/reopen.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/app/chain
import ../../../src/app/checkpoint/[identity as checkpoint_identity,
    transfer as checkpoint_transfer, writer as checkpoint_writer, file as checkpoint_file]
import ../../../src/chain/genesis
import ../../../src/codec/bounded
import ../../support/[application_checkpoint_context, arc_evidence]
const FileName = "application-checkpoint-writer"
proc cycle(expected: ApplicationCheckpointIdentity) =
  ## Complete owner/lock/read/recovery lifetimes retire before each occupancy observation.
  var writer = default(ApplicationCheckpointWriter)
  defer: discard writer.close()
  assert writer.openApplicationCheckpointWriter(FileName) == ApplicationCheckpointFileError.None
  assert writer.load(expected, genesisStoreLimits(), ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.None
  assert writer.close() == ApplicationCheckpointFileError.None
proc main() {.raises.} =
  ## Source path mutation, repeated open, simultaneous contender and closed calls cannot redirect or duplicate one namespace.
  var path = FileName
  var lockPath = FileName & ".lock"
  defer:
    discard posix.unlink(path.toCString())
    discard posix.unlink(lockPath.toCString()) # Only explicit closed owners precede test-only lock inode teardown.
  let owner = checkpointFixture()
  let expected = captureApplicationCheckpointIdentity(owner).value
  var writer = default(ApplicationCheckpointWriter)
  defer: discard writer.close()
  var waiting = default(ApplicationCheckpointWriter)
  defer: discard waiting.close()
  assert not writer.opened and writer.close() == ApplicationCheckpointFileError.None
  assert writer.save(owner, ByteLimit(100000)).error == ApplicationCheckpointFileError.Uninitialized
  assert writer.load(expected, genesisStoreLimits(), ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.Uninitialized
  assert writer.openApplicationCheckpointWriter("") == ApplicationCheckpointFileError.InvalidPath
  var source = FileName
  assert writer.openApplicationCheckpointWriter(source) == ApplicationCheckpointFileError.None
  source[0] = 'x' # The native owner must retain a deep independent destination.
  assert writer.openApplicationCheckpointWriter("different-path") ==
      ApplicationCheckpointFileError.Busy
  assert waiting.openApplicationCheckpointWriter(FileName) == ApplicationCheckpointFileError.Busy
  var prepared = prepareApplicationCheckpoint(owner, ByteLimit(100000))
  assert writer.save(prepared, ByteLimit(100000)).error == ApplicationCheckpointFileError.None
  assert writer.load(expected, genesisStoreLimits(), ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.None
  assert writer.close() == ApplicationCheckpointFileError.None
  assert waiting.openApplicationCheckpointWriter(FileName) == ApplicationCheckpointFileError.None
  assert waiting.load(expected, genesisStoreLimits(), ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.None
  assert waiting.close() == ApplicationCheckpointFileError.None
  cycle(expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(expected) # Each native lock/path and recovered map owner retires without accumulating resources.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_checkpoint_writer", 1000, before, after)
  echo "PASS application checkpoint writer: copied paths, exclusive ownership, bounded recovery and closed lifetimes"
try:
  main() # Native/fixture setup errors remain nonzero failures.
except:
  quit(2)
