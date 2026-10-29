# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_bank_arc_release"}

## Recovery selects one exact locked slot and never elevates checksums or intact orphan files into chain trust.

import std/[assertions, syncio]
import std/posix/posix
import ../../../src/state/checkpoint/[bank as checkpoint_bank, head as checkpoint_head,
    file as checkpoint_file]
import ../../../src/state/[checkpoint, store]
import ../../../src/lib/atomic/file as atomic_file
import ../../../src/codec/state/[trie as state_trie, layout as state_layout]
import ../../../src/codec/bounded
import ../../support/arc_evidence

const Prefix = "state-checkpoint-bank"
proc policy(): StateStoreLimits =
  ## Explicit complete-map construction and restoration ceilings stay independent of file metadata.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(200), nodes: TrieNodeLimit(1024)),
    writes: ElementLimit(4), writeValueBytes: ByteLimit(200))
proc select(slot: CheckpointSlot, root: StateRoot) =
  ## Test setup writes independently encoded local metadata, including intentionally inconsistent selections.
  let head = newCheckpointHead(CheckpointGeneration(7), slot, root)
  assert replaceAtomicFile(Prefix & ".head", encodeCheckpointHead(head, ByteLimit(1000)).value,
    ByteLimit(1000)) == AtomicFileError.None
proc cycle(expected: StateRoot) =
  ## Host-only lock/read/restore/refusal/retirement cycles drop all complete-map and native ownership.
  var bank = default(CheckpointBank)
  defer: discard bank.close()
  assert bank.openCheckpointBank(Prefix) == CheckpointBankError.None
  assert bank.restore(expected, policy(), ByteLimit(1000)).error == CheckpointBankError.None
  assert bank.restore(expected, policy(), ByteLimit(0)).error == CheckpointBankError.LimitExceeded
  assert bank.close() == CheckpointBankError.None
proc main() =
  ## Intact alternate files cannot authorize a different selection, repair corruption or replace external trust.
  for suffix in [".head", ".0", ".1", ".0.tmp.orphan"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # A clean test-owned namespace makes absent-head/slot controls independent of prior runs.
  defer:
    for suffix in [".head", ".head.lock", ".0", ".1", ".0.tmp.orphan"]:
      var path = Prefix & suffix
      discard posix.unlink(path.toCString()) # Resource owners below retire before their test-only stable lock inode is removed.
  let empty = newStateStore([], policy()).value.snapshot.value
  var keyBytes = default(array[31, byte])
  keyBytes[0] = 1
  let key = StateKey(keyBytes)
  let full = newStateStore([StateEntry(key: key, value: @[9'u8])], policy()).value.snapshot.value
  let expected = full.commitment.root
  var bank = default(CheckpointBank)
  defer: discard bank.close()
  assert bank.restore(expected, policy(), ByteLimit(1000)).error ==
      CheckpointBankError.Uninitialized
  assert bank.openCheckpointBank("") == CheckpointBankError.InvalidPath
  var source = Prefix
  assert bank.openCheckpointBank(source) == CheckpointBankError.None
  source[0] = 'x'
  assert bank.openCheckpointBank("other-bank") == CheckpointBankError.Busy
  var contender = default(CheckpointBank)
  defer: discard contender.close()
  assert contender.openCheckpointBank(Prefix) == CheckpointBankError.Busy
  assert bank.selectedHead().error == CheckpointBankError.IoFailure
  assert saveFullCheckpoint(Prefix & ".0", empty, ByteLimit(1000)).error == CheckpointFileError.None
  assert saveFullCheckpoint(Prefix & ".1", full, ByteLimit(1000)).error == CheckpointFileError.None
  select(CheckpointSlot.Second, expected)
  let head = bank.selectedHead().value
  assert uint64(head.generation) == 7 and head.slot == CheckpointSlot.Second
  let restored = bank.restore(expected, policy(), ByteLimit(1000)).value
  assert restored.snapshot.value.lookup(key).value.bytes == @[9'u8]
  assert bank.restore(empty.commitment.root, policy(), ByteLimit(1000)).error ==
      CheckpointBankError.RootMismatch
  assert bank.restore(expected, policy(), ByteLimit(0)).error == CheckpointBankError.LimitExceeded
  var denied = policy()
  denied.trie.items = ElementLimit(0)
  let refused = bank.restore(expected, denied, ByteLimit(1000))
  assert refused.error == CheckpointBankError.InvalidCheckpoint
  assert refused.checkpointError == CheckpointError.LimitExceeded
  select(CheckpointSlot.First, expected)
  let inconsistent = bank.restore(expected, policy(), ByteLimit(1000))
  assert inconsistent.error == CheckpointBankError.InvalidCheckpoint
  assert inconsistent.checkpointError == CheckpointError.RootMismatch # Intact second slot must not repair a mismatched selected root.
  assert replaceAtomicFile(Prefix & ".head", [0'u8], ByteLimit(1)) == AtomicFileError.None
  let malformed = bank.restore(expected, policy(), ByteLimit(1000))
  assert malformed.error == CheckpointBankError.InvalidHead
  assert malformed.headError == CheckpointHeadError.InvalidFormat
  assert replaceAtomicFile(Prefix & ".head", newSeq[byte](CheckpointHeadBytes + 1), ByteLimit(
      1000)) == AtomicFileError.None
  assert bank.selectedHead().error == CheckpointBankError.LimitExceeded
  select(CheckpointSlot.First, empty.commitment.root)
  var selectedPath = Prefix & ".0"
  assert posix.unlink(selectedPath.toCString()) == 0
  assert saveFullCheckpoint(Prefix & ".1", empty, ByteLimit(1000)).error == CheckpointFileError.None
  assert saveFullCheckpoint(Prefix & ".0.tmp.orphan", empty, ByteLimit(1000)).error ==
      CheckpointFileError.None
  assert bank.restore(empty.commitment.root, policy(), ByteLimit(1000)).error ==
      CheckpointBankError.IoFailure # Neither intact inactive nor temporary files are candidates.
  assert restored.snapshot.value.lookup(key).value.bytes == @[
      9'u8] # Later on-disk replacement cannot mutate a retained restored map.
  select(CheckpointSlot.Second, empty.commitment.root)
  assert bank.close() == CheckpointBankError.None
  assert bank.close() == CheckpointBankError.None
  assert bank.selectedHead().error == CheckpointBankError.Uninitialized
  assert contender.openCheckpointBank(Prefix) == CheckpointBankError.None
  assert contender.close() == CheckpointBankError.None
  cycle(empty.commitment.root)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(empty.commitment.root) # All snapshots and descriptors retire before the next parent-thread observation.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_bank", 1000, before, after)
  echo "PASS checkpoint bank recovery: locked exact selection, independent trust and no orphan fallback"
main()
