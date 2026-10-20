# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Abrupt child process exit releases worker locks and preserves only actually published checkpoint generations.

import std/[assertions, syncio, monotimes, times]
import std/posix/posix
import ../../../src/state/[checkpoint_worker, checkpoint_bank, checkpoint_head, checkpoint_transfer,
    checkpoint, store]
import ../../../src/lib/atomic_file
import ../../../src/codec/[state_trie, state_layout, bounded]

const
  Directory = "state-checkpoint-worker-restart"
  Prefix = Directory & "/checkpoint"
proc policy(): StateStoreLimits =
  ## Distinct original and candidate roots expose any accidental staged-buffer adoption.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(2), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(200), nodes: TrieNodeLimit(1024)), writes: ElementLimit(2),
        writeValueBytes: ByteLimit(200))
proc clearFiles() =
  ## Parent-only cleanup follows every child join and descriptor retirement, leaving unexpected temporaries observable.
  for suffix in [".head", ".head.lock", ".0", ".1"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # This private test directory contains no unrelated caller data.
proc attempt(prior, candidate: StateStoreSnapshot, mode: int) {.raises.} =
  ## Exit before dispatch, after cancellation or after durable completion; no live worker/lock is inherited across fork.
  clearFiles()
  var setup = default(CheckpointBank)
  assert setup.openCheckpointBank(Prefix) == CheckpointBankError.None
  let initial = setup.initialize(prior, ByteLimit(1000)).value
  assert setup.close() == CheckpointBankError.None
  let originalHead = readBoundedFile(Prefix & ".head", ByteLimit(1000)).value
  let originalSlot = readBoundedFile(Prefix & ".0", ByteLimit(1000)).value
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var worker = default(CheckpointWorker)
    if worker.start(Prefix) != CheckpointBankError.None: posix.exitnow(3)
    var prepared = prepareFullCheckpoint(candidate, ByteLimit(1000))
    let admitted = worker.stage(prepared, CheckpointOperation.Advance, initial, ByteLimit(1000))
    if admitted.error != CheckpointWorkerError.None: posix.exitnow(4)
    let ticket = admitted.value
    if mode == 1:
      if not worker.cancel(ticket): posix.exitnow(
          5) # This child exits while retaining an unacknowledged cancellation.
    elif mode == 2:
      if not worker.begin(ticket): posix.exitnow(6)
      let started = getMonoTime()
      while worker.phase != CheckpointWorkerPhase.Done:
        if (getMonoTime() - started).inSeconds >= 20: posix.exitnow(7)
        var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
        var remaining = default(Timespec)
        discard nanosleep(requested, remaining) # Only the test waits; publication remains one condition-driven native operation.
      let outcome = worker.peek(ticket)
      if outcome.kind != CheckpointCompletionKind.Completed or outcome.value.error !=
          CheckpointBankError.None:
        posix.exitnow(8) # A merely staged or failed publication cannot satisfy the committed-exit witness.
    else:
      discard # Staged-only exit deliberately skips dispatch and leaves both selector and inactive slot untouched.
    posix.exitnow(0) # Intentionally skip collection/join/destruction: process exit must release native lock descriptors.
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var ignored = 0.cint
      discard posix.waitpid(child, ignored, 0) # No failed parent assertion leaves an unjoined child.
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0, "abrupt checkpoint worker exit child"
  var bank = default(CheckpointBank)
  defer: discard bank.close()
  assert bank.openCheckpointBank(Prefix) == CheckpointBankError.None # Kernel process retirement released the child's cooperative lock.
  let expected = if mode == 2: candidate else: prior
  let restored = bank.restore(expected.commitment.root, policy(), ByteLimit(1000)).value
  assert encodeFullCheckpoint(restored.snapshot.value, ByteLimit(1000)).value ==
      encodeFullCheckpoint(expected, ByteLimit(1000)).value
  assert uint64(bank.selectedHead().value.generation) == (if mode == 2: 1'u64 else: 0'u64)
  assert readBoundedFile(Prefix & ".0", ByteLimit(1000)).value == originalSlot
  if mode == 2:
    assert readBoundedFile(Prefix & ".1", ByteLimit(1000)).value == encodeFullCheckpoint(candidate,
        ByteLimit(1000)).value
  else:
    assert readBoundedFile(Prefix & ".head", ByteLimit(1000)).value == originalHead
    assert readBoundedFile(Prefix & ".1", ByteLimit(1000)).error ==
        AtomicFileError.IoFailure # Neither an unstarted nor cancelled buffer creates canonical inactive data.
  assert bank.close() == CheckpointBankError.None
proc main() {.raises.} =
  ## Real process retirement is distinct from power loss, native mid-write termination or cross-process ARC accounting.
  var directory = Directory
  assert posix.mkdir(directory.toCString(), Mode(0o700)) == 0
  defer:
    clearFiles()
    discard posix.rmdir(directory.toCString()) # Preserve an earlier assertion while attempting private-directory cleanup.
  let prior = newStateStore([StateEntry(key: default(StateKey), value: @[1'u8])], policy()).value.snapshot.value
  let candidate = newStateStore([StateEntry(key: default(StateKey), value: @[2'u8])], policy()).value.snapshot.value
  for mode in 0..<3:
    attempt(prior, candidate, mode) # Each child starts its own bank/thread only after a lock-free fork boundary.
  clearFiles()
  assert posix.rmdir(directory.toCString()) == 0 # Known boundary exits leave no operation temporary files behind.
  echo "PASS checkpoint worker restart: abrupt staged, cancelled and durable-completion process exits"
try:
  main() # Native startup or process errors must remain suite failures.
except:
  quit(2)
