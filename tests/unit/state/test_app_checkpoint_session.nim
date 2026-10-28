# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_checkpoint_session_arc_release"}

## Joined outcomes survive repeated close and block restart until explicit receipt acknowledgement.
import std/assertions
import std/syncio
import std/monotimes
import std/times
import std/posix/posix
import ../../../src/app/checkpoint_session as app_checkpoint_session
import ../../../src/app/checkpoint_worker as app_checkpoint_worker
import ../../../src/app/checkpoint_file as app_checkpoint_file
import ../../../src/app/checkpoint_transfer as app_checkpoint_transfer
import ../../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../../src/codec/bounded as codec_bounded
import ../../support/app_checkpoint_worker_context
import ../../support/app_checkpoint_context
import ../../support/testing_arc_evidence
const FileName = "application-checkpoint-session"
proc waitDone(session: var ApplicationCheckpointSession) =
  ## Bounded test polling observes scalar lifecycle only.
  let started = getMonoTime()
  while session.phase != ApplicationCheckpointWorkerPhase.Done:
    assert (getMonoTime() - started).inSeconds < 20
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Yield only in this native test.
proc cycle(session: var ApplicationCheckpointSession) {.raises.} =
  ## Close on staged work retains Cancelled until explicit acknowledgement; every restart receives fresh identity.
  assert session.start(FileName) == ApplicationCheckpointFileError.None
  var source = detachedApplicationCheckpoint()
  discard session.stage(source, ByteLimit(100000)).value
  session.close()
  assert session.shutdownPending and not session.opened
  assert session.shutdown.completion.kind == ApplicationCheckpointCompletionKind.Cancelled
  assert session.takeShutdown().retirementError == ApplicationCheckpointFileError.None
  assert not session.shutdownPending
proc main() {.raises.} =
  ## Real completed I/O cannot be forgotten by idempotent aggregate cleanup or overwritten by restart.
  defer:
    for suffix in ["", ".lock"]:
      var path = FileName & suffix
      discard posix.unlink(path.toCString()) # Session owners below retire before test-only lock cleanup.
  var session = default(ApplicationCheckpointSession)
  defer: session.close()
  session.close()
  assert not session.shutdownPending and not session.opened
  assert session.start("") == ApplicationCheckpointFileError.InvalidPath
  assert session.start(FileName) == ApplicationCheckpointFileError.None
  assert session.start(FileName) == ApplicationCheckpointFileError.Busy
  var source = detachedApplicationCheckpoint(CheckpointFixtureVariant.Profile)
  let expected = source.identity
  let ticket = session.stage(source, ByteLimit(100000)).value
  assert session.begin(ticket)
  session.waitDone()
  session.close()
  assert session.shutdownPending and not session.opened
  assert session.shutdown.completion.kind == ApplicationCheckpointCompletionKind.Completed
  assert sameApplicationCheckpoint(session.shutdown.completion.value.value, expected)
  session.close()
  session.close()
  assert session.start(FileName) == ApplicationCheckpointFileError.Busy
  assert sameApplicationCheckpoint(session.shutdown.completion.value.value, expected)
  var relocated = move(session) # Closed ownership may carry its fixed receipt to a new owner.
  defer: relocated.close()
  assert not session.shutdownPending and relocated.shutdownPending
  assert relocated.start(FileName) == ApplicationCheckpointFileError.Busy
  let acknowledged = relocated.takeShutdown()
  assert sameApplicationCheckpoint(acknowledged.completion.value.value, expected)
  assert not relocated.shutdownPending
  assert relocated.start(FileName) == ApplicationCheckpointFileError.None
  assert not relocated.begin(ticket) # Restart cannot revive a ticket retained with an old receipt.
  var next = detachedApplicationCheckpoint()
  let second = relocated.stage(next, ByteLimit(100000)).value
  assert relocated.cancel(second)
  assert relocated.collect(second).kind == ApplicationCheckpointCompletionKind.Cancelled
  relocated.close()
  assert not relocated.shutdownPending # Acknowledged work creates no duplicate shutdown receipt.
  cycle(relocated)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(relocated) # Each thread, lock, host identity and sole prepared buffer retires before measurement.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_checkpoint_session", 1000, before, after)
  echo "PASS application checkpoint session: retained joined outcomes, acknowledgement-gated restart and inactive receipt moves"
try:
  main() # Thread/fixture/native setup errors remain failures.
except:
  quit(2)
