# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed parent address and selected shutdown receipt access enforce real lifecycle contracts.
import std/assertions
import std/cmdline
import std/syncio
import ../../src/app/checkpoint_session as app_checkpoint_session
import ../../src/app/checkpoint_worker as app_checkpoint_worker
import ../../src/app/checkpoint_file as app_checkpoint_file
import ../../src/codec/bounded as codec_bounded
import ../support/app_checkpoint_worker_context
proc inspect(session: ApplicationCheckpointSession) =
  ## Only retained actual joined work grants a shutdown receipt.
  discard session.shutdown
proc take(session: var ApplicationCheckpointSession) =
  ## Default/already-acknowledged receipts grant no acknowledgement authority.
  discard session.takeShutdown()
proc forgotten() {.raises.} =
  ## Actual thread startup precedes checked composite destruction.
  var session = default(ApplicationCheckpointSession)
  assert session.start("build/application-checkpoint-session-unclosed") ==
      ApplicationCheckpointFileError.None
proc main() {.raises.} =
  ## Staged joined cancellation is a genuine receipt control, and inactive owners may move.
  let mode = paramStr(1)
  if mode == "unclosed":
    forgotten() # A managed parent cannot abandon its live fixed-address child.
  elif mode == "moved":
    var session = default(ApplicationCheckpointSession)
    assert session.start("build/application-checkpoint-session-moved") ==
        ApplicationCheckpointFileError.None
    var moved = move(session)
    moved.close() # Relocation must fail before a native thread's address can become dangling.
  elif mode == "shutdown":
    let session = default(ApplicationCheckpointSession)
    inspect(session) # Default owners have no retained receipt.
  elif mode == "take":
    var session = default(ApplicationCheckpointSession)
    take(session) # A missing receipt cannot be acknowledged.
  else:
    assert mode == "positive"
    var session = default(ApplicationCheckpointSession)
    defer: session.close()
    assert session.start("build/application-checkpoint-session-guard") ==
        ApplicationCheckpointFileError.None
    var source = detachedApplicationCheckpoint()
    discard session.stage(source, ByteLimit(100000)).value
    session.close()
    inspect(session)
    take(session)
    var moved = move(session)
    moved.close()
try:
  main() # Setup exceptions are not checked assertion witnesses.
except:
  quit(2)
