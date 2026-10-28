# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real child-only POSIX file-size ceilings distinguish inactive staging from selector publication rollback.
## An empty candidate is smaller than its head so the kernel can fail precisely after durable staging.

import std/assertions
import std/syncio
import std/posix/posix
import ../../support/testing_file_size_ceiling
import ../../../src/state/checkpoint_bank as state_checkpoint_bank
import ../../../src/state/checkpoint_head as state_checkpoint_head
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/store as state_store
import ../../../src/lib/atomic_file as lib_atomic_file
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded



const
  Directory = "state-bank-write-failure"
  Prefix = Directory & "/checkpoint"
proc policy(): StateStoreLimits =
  ## Distinct nonempty prior and empty candidate roots reveal incorrect old-generation adoption.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(1), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(100), nodes: TrieNodeLimit(1024)), writes: ElementLimit(1),
        writeValueBytes: ByteLimit(100))
proc clearFiles() =
  ## Parent-only teardown removes known committed files while leaving orphan temporaries observable through final rmdir.
  for suffix in [".head", ".head.lock", ".0", ".1"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # Every child is joined and all cooperating bank descriptors are already closed.
proc attempt(prior, candidate: StateStoreSnapshot, ceiling: uint64, staged, succeeds: bool) =
  ## The selected old slot survives every refusal, even after the new inactive data became durable.
  clearFiles()
  var setup = default(CheckpointBank)
  assert setup.openCheckpointBank(Prefix) == CheckpointBankError.None
  let initial = setup.initialize(prior, ByteLimit(1000)).value
  assert setup.close() == CheckpointBankError.None # No live lock owner crosses fork or aliases retirement obligations.
  let originalHead = readBoundedFile(Prefix & ".head", ByteLimit(1000)).value
  let originalSlot = readBoundedFile(Prefix & ".0", ByteLimit(1000)).value
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    let restricted = restrictFileSize(ceiling)
    if restricted != 0: posix.exitnow(restricted) # A setup error must remain distinct from the expected kernel write refusal.
    var bank = default(CheckpointBank)
    if bank.openCheckpointBank(Prefix) != CheckpointBankError.None: posix.exitnow(6)
    let outcome = bank.advance(initial, candidate, ByteLimit(1000))
    let wanted = if succeeds: CheckpointBankError.None else: CheckpointBankError.IoFailure
    if outcome.error != wanted: posix.exitnow(7) # Producer limits or fabricated success cannot satisfy the expected native I/O failure.
    let expectedRoot = if succeeds: candidate.commitment.root else: prior.commitment.root
    if bank.restore(expectedRoot, policy(), ByteLimit(1000)).error != CheckpointBankError.None:
      posix.exitnow(8) # Child observation must follow the selected complete map, never the newest parseable file.
    if bank.close() != CheckpointBankError.None: posix.exitnow(
        9) # Each real child retires its own native lock before abrupt ARC-safe exit.
    posix.exitnow(0) # Do not destruct copied parent ARC graphs after fork; no cross-process ARC occupancy claim is made.
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var ignored = 0.cint
      discard posix.waitpid(child, ignored, 0) # Every bounded child is joined even when a parent assertion fails.
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0, "bank real kernel write-limit child"
  var bank = default(CheckpointBank)
  defer: discard bank.close()
  assert bank.openCheckpointBank(Prefix) == CheckpointBankError.None
  let expected = if succeeds: candidate else: prior
  let head = bank.selectedHead().value
  assert uint64(head.generation) == (if succeeds: 1'u64 else: 0'u64)
  assert head.slot == (if succeeds: CheckpointSlot.Second else: CheckpointSlot.First)
  let restored = bank.restore(expected.commitment.root, policy(), ByteLimit(1000)).value
  assert encodeFullCheckpoint(restored.snapshot.value, ByteLimit(1000)).value ==
      encodeFullCheckpoint(expected, ByteLimit(1000)).value
  assert readBoundedFile(Prefix & ".0", ByteLimit(1000)).value ==
      originalSlot # No failing or successful first advancement may replace the old selected data.
  if not succeeds:
    assert readBoundedFile(Prefix & ".head", ByteLimit(1000)).value ==
        originalHead # Pre-rename selector failure preserves every original metadata octet.
  if staged:
    let bytes = readBoundedFile(Prefix & ".1", ByteLimit(1000)).value
    assert bytes == encodeFullCheckpoint(candidate, ByteLimit(
        1000)).value # Selector failures must actually have passed complete inactive staging.
  else:
    assert readBoundedFile(Prefix & ".1", ByteLimit(1000)).error ==
        AtomicFileError.IoFailure # Inactive write failure never publishes a partial canonical slot.
  assert bank.close() == CheckpointBankError.None
proc main() =
  ## Six actual zero/partial write failures and exact/ample success controls separately witness both transaction stages.
  var directory = Directory
  assert posix.mkdir(directory.toCString(), Mode(0o700)) == 0
  defer:
    clearFiles()
    discard posix.rmdir(directory.toCString()) # Best-effort cleanup preserves the primary failure verdict on early return.
  let prior = newStateStore([StateEntry(key: default(StateKey), value: @[7'u8])], policy()).value.snapshot.value
  let candidate = newStateStore([], policy()).value.snapshot.value
  let stagedSize = uint64(encodeFullCheckpoint(candidate, ByteLimit(1000)).value.len)
  assert stagedSize < uint64(CheckpointHeadBytes)
  for ceiling in [0'u64, 1'u64, stagedSize - 1]:
    attempt(prior, candidate, ceiling, false, false) # These kernel limits fail before inactive-slot rename.
  for ceiling in [stagedSize, 64'u64, uint64(CheckpointHeadBytes - 1)]:
    attempt(prior, candidate, ceiling, true, false) # Empty inactive data is complete and durable; only selector writing can fail.
  for ceiling in [uint64(CheckpointHeadBytes), uint64(CheckpointHeadBytes + 1)]:
    attempt(prior, candidate, ceiling, true, true) # The same implementation succeeds at exact and ample selector size.
  clearFiles()
  assert posix.rmdir(directory.toCString()) == 0 # An empty directory proves all operation-owned temporary siblings were removed.
  echo "PASS bank write failures: six kernel refusals across two stages, exact controls and selected-state rollback"
main()
