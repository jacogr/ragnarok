# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_bank_verify_arc_release"}

## Trusted selected-map verification returns only scalar metadata after retiring temporary complete state.

import std/[assertions, syncio]
import std/posix/posix
import ../../../src/state/[checkpoint_bank, checkpoint_transfer, checkpoint_head, checkpoint, store]
import ../../../src/lib/atomic_file
import ../../../src/codec/[state_trie, state_layout, bounded]
import ../../support/arc_evidence

const Prefix = "state-bank-verify"
proc policy(): StateStoreLimits =
  ## Full-map restore policy remains separate from publication's explicit byte ceiling.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(200), nodes: TrieNodeLimit(1024)), writes: ElementLimit(4),
        writeValueBytes: ByteLimit(200))
proc detached(value: byte): PreparedCheckpoint =
  ## All original snapshot/store aliases retire before a prepared bank caller receives its sole buffer.
  var key = default(array[31, byte])
  key[0] = 1
  let snapshot = newStateStore([StateEntry(key: StateKey(key), value: @[value])], policy()).value.snapshot.value
  prepareFullCheckpoint(snapshot, ByteLimit(1000))
proc cycle(bank: var CheckpointBank, root: StateRoot, head: CheckpointHead) =
  ## Verified scalar receipts retain no decoded map or transient file buffer between calls.
  let verified = bank.verify(root, policy(), ByteLimit(1000)).value
  assert verified.slot == head.slot and uint64(verified.generation) == uint64(head.generation)
  assert array[32, byte](verified.root) == array[32, byte](root)
proc main() =
  ## Trust, format, byte/map limits and selected-slot availability all precede a usable verified receipt.
  for suffix in [".head", ".0", ".1"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # Reset only this suite's namespace before cooperative locking.
  defer:
    for suffix in [".head", ".head.lock", ".0", ".1"]:
      var path = Prefix & suffix
      discard posix.unlink(path.toCString()) # Joined/closed owners precede removal of test-only lock inodes.
  var bank = default(CheckpointBank)
  defer: discard bank.close()
  assert bank.verify(default(StateRoot), policy(), ByteLimit(1000)).error ==
      CheckpointBankError.Uninitialized
  assert bank.openCheckpointBank(Prefix) == CheckpointBankError.None
  assert bank.verify(default(StateRoot), policy(), ByteLimit(1000)).error ==
      CheckpointBankError.IoFailure
  var first = detached(1)
  let head = bank.initialize(first, ByteLimit(1000)).value
  let originalHead = readBoundedFile(Prefix & ".head", ByteLimit(1000)).value
  let originalSlot = readBoundedFile(Prefix & ".0", ByteLimit(1000)).value
  assert bank.verify(default(StateRoot), policy(), ByteLimit(1000)).error ==
      CheckpointBankError.RootMismatch
  var narrow = policy()
  narrow.trie.items = ElementLimit(0)
  let refused = bank.verify(first.root, narrow, ByteLimit(1000))
  assert refused.error == CheckpointBankError.InvalidCheckpoint and refused.checkpointError ==
      CheckpointError.LimitExceeded
  assert bank.verify(first.root, policy(), ByteLimit(uint64(first.byteLength - 1))).error ==
      CheckpointBankError.LimitExceeded
  cycle(bank, first.root, head)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(bank, first.root, head) # Each temporary decoded complete map is destroyed on this caller thread.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_bank_verify", 1000, before, after)
  assert readBoundedFile(Prefix & ".head", ByteLimit(1000)).value == originalHead
  assert readBoundedFile(Prefix & ".0", ByteLimit(1000)).value == originalSlot
  var corrupt = originalSlot
  corrupt[0] = corrupt[0] xor 1
  assert replaceAtomicFile(Prefix & ".0", corrupt, ByteLimit(1000)) == AtomicFileError.None
  let invalid = bank.verify(first.root, policy(), ByteLimit(1000))
  assert invalid.error == CheckpointBankError.InvalidCheckpoint and invalid.checkpointError ==
      CheckpointError.InvalidFormat
  assert replaceAtomicFile(Prefix & ".1", originalSlot, ByteLimit(1000)) == AtomicFileError.None
  var selected = Prefix & ".0"
  assert posix.unlink(selected.toCString()) == 0
  assert bank.verify(first.root, policy(), ByteLimit(1000)).error ==
      CheckpointBankError.IoFailure # The intact orphan cannot substitute for a missing selected map.
  assert replaceAtomicFile(Prefix & ".0", originalSlot, ByteLimit(1000)) == AtomicFileError.None
  cycle(bank, first.root, head)
  assert bank.restore(first.root, policy(), ByteLimit(1000)).error == CheckpointBankError.None
  assert bank.close() == CheckpointBankError.None
  echo "PASS checkpoint bank verification: independent trust, exact selection and retired complete maps"
main()
