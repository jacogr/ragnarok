# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_advance_arc_release"}

## Local compare-and-publish advances only after durable old selection and inactive complete-map staging.

import std/[assertions, syncio]
import std/posix/posix
import ../../../src/state/checkpoint/[bank as checkpoint_bank, head as checkpoint_head]
import ../../../src/state/[checkpoint, store]
import ../../../src/lib/atomic/file as atomic_file
import ../../../src/codec/state/[trie as state_trie, layout as state_layout]
import ../../../src/codec/bounded
import ../../support/arc_evidence

const Prefix = "state-checkpoint-advance"
proc policy(): StateStoreLimits =
  ## Explicit complete-map ceilings are independent of local generation count.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(200), nodes: TrieNodeLimit(1024)), writes: ElementLimit(4),
        writeValueBytes: ByteLimit(200))
proc snapshot(value: byte): StateStoreSnapshot =
  ## Distinct full-map roots make stale-root and selected-data preservation independently observable.
  var key = default(array[31, byte])
  key[0] = 1
  newStateStore([StateEntry(key: StateKey(key), value: @[value])], policy()).value.snapshot.value
proc cycle(bank: var CheckpointBank, source: StateStoreSnapshot) =
  ## Repeated advancement, stale-token refusal and anchored restoration drop every temporary candidate/head.
  let previous = bank.selectedHead().value
  let head = bank.advance(previous, source, ByteLimit(1000)).value
  assert uint64(head.generation) == uint64(previous.generation) + 1
  assert bank.advance(previous, source, ByteLimit(1000)).error == CheckpointBankError.StaleHead
  assert bank.restore(source.commitment.root, policy(), ByteLimit(1000)).error ==
      CheckpointBankError.None
proc main() =
  ## Both alternations, every stale field, no-write refusals and real inactive rename failure preserve the selected map.
  for suffix in [".head", ".0", ".1"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # Test-only namespace reset precedes native acquisition.
  var inactivePath = Prefix & ".1"
  var lockPath = Prefix & ".head.lock"
  defer:
    for suffix in [".head", ".0", ".1"]:
      var path = Prefix & suffix
      discard posix.unlink(path.toCString()) # The owner below retires before test-only stable lock removal.
    discard posix.rmdir(inactivePath.toCString())
    discard posix.unlink(lockPath.toCString())
  let first = snapshot(1)
  let second = snapshot(2)
  let third = snapshot(3)
  var bank = default(CheckpointBank)
  defer: discard bank.close()
  assert bank.advance(default(CheckpointHead), first, ByteLimit(1000)).error ==
      CheckpointBankError.Uninitialized
  assert bank.openCheckpointBank(Prefix) == CheckpointBankError.None
  assert bank.advance(default(CheckpointHead), first, ByteLimit(1000)).headError ==
      CheckpointHeadError.Uninitialized
  let initial = bank.initialize(first, ByteLimit(1000)).value
  let firstBytes = readBoundedFile(Prefix & ".0", ByteLimit(1000)).value
  let initialHeadBytes = readBoundedFile(Prefix & ".head", ByteLimit(1000)).value
  assert bank.advance(initial, default(StateStoreSnapshot), ByteLimit(1000)).checkpointError ==
      CheckpointError.Uninitialized
  assert bank.advance(initial, second, ByteLimit(0)).checkpointError ==
      CheckpointError.LimitExceeded
  for wrong in [newCheckpointHead(CheckpointGeneration(1), initial.slot, initial.root),
      newCheckpointHead(initial.generation, CheckpointSlot.Second, initial.root),
      newCheckpointHead(initial.generation, initial.slot, second.commitment.root)]:
    assert bank.advance(wrong, second, ByteLimit(1000)).error ==
        CheckpointBankError.StaleHead # All three fields constrain local publication independently.
  assert readBoundedFile(Prefix & ".head", ByteLimit(1000)).value == initialHeadBytes
  assert posix.mkdir(inactivePath.toCString(), Mode(0o700)) == 0
  assert bank.advance(initial, second, ByteLimit(1000)).error == CheckpointBankError.IoFailure
  assert readBoundedFile(Prefix & ".head", ByteLimit(1000)).value == initialHeadBytes
  assert readBoundedFile(Prefix & ".0", ByteLimit(1000)).value == firstBytes
  assert bank.restore(first.commitment.root, policy(), ByteLimit(1000)).error ==
      CheckpointBankError.None
  assert posix.rmdir(inactivePath.toCString()) == 0
  let next = bank.advance(initial, second, ByteLimit(1000)).value
  assert uint64(next.generation) == 1 and next.slot == CheckpointSlot.Second
  assert readBoundedFile(Prefix & ".0", ByteLimit(1000)).value ==
      firstBytes # The old selected slot is untouched until another head is durable.
  let secondBytes = readBoundedFile(Prefix & ".1", ByteLimit(1000)).value
  let final = bank.advance(next, third, ByteLimit(1000)).value
  assert uint64(final.generation) == 2 and final.slot == CheckpointSlot.First
  assert readBoundedFile(Prefix & ".1", ByteLimit(1000)).value == secondBytes
  assert bank.restore(third.commitment.root, policy(), ByteLimit(1000)).error ==
      CheckpointBankError.None
  assert bank.restore(second.commitment.root, policy(), ByteLimit(1000)).error ==
      CheckpointBankError.RootMismatch
  assert bank.advance(next, second, ByteLimit(1000)).error == CheckpointBankError.StaleHead
  let exhausted = newCheckpointHead(CheckpointGeneration(high(uint64)), final.slot, final.root)
  let exhaustedBytes = encodeCheckpointHead(exhausted, ByteLimit(1000)).value
  assert replaceAtomicFile(Prefix & ".head", exhaustedBytes, ByteLimit(1000)) ==
      AtomicFileError.None
  let refusal = bank.advance(exhausted, second, ByteLimit(1000))
  assert refusal.error == CheckpointBankError.InvalidHead and refusal.headError ==
      CheckpointHeadError.GenerationExhausted
  assert readBoundedFile(Prefix & ".head", ByteLimit(1000)).value == exhaustedBytes
  assert readBoundedFile(Prefix & ".1", ByteLimit(1000)).value ==
      secondBytes # Exhaustion refuses before any inactive-slot replacement.
  assert replaceAtomicFile(Prefix & ".head", encodeCheckpointHead(final, ByteLimit(1000)).value,
      ByteLimit(1000)) == AtomicFileError.None
  cycle(bank, first)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(bank, first) # No canonical snapshot or head is retained by the bank between host-thread calls.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_advance", 1000, before, after)
  assert bank.close() == CheckpointBankError.None
  assert bank.advance(final, first, ByteLimit(1000)).error == CheckpointBankError.Uninitialized
  echo "PASS checkpoint advancement: exact expected head, durable selection and inactive-slot rollback"
main()
