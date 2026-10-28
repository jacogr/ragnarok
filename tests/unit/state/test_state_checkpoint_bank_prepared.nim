# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_bank_prepared_arc_release"}

## Detached prepared-byte publication shares the exact bank transaction without borrowing the retired source graph.

import std/assertions
import std/syncio
import std/posix/posix
import ../../../src/state/checkpoint_bank as state_checkpoint_bank
import ../../../src/state/checkpoint_transfer as state_checkpoint_transfer
import ../../../src/state/checkpoint_head as state_checkpoint_head
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/store as state_store
import ../../../src/lib/atomic_file as lib_atomic_file
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded
import ../../support/testing_arc_evidence

const Prefix = "state-bank-prepared"
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
proc cycle(bank: var CheckpointBank, prepared: PreparedCheckpoint) =
  ## Reuse one stable private buffer synchronously while each generation's metadata and restoration retire.
  let old = bank.selectedHead().value
  let head = bank.advance(old, prepared, ByteLimit(1000)).value
  assert uint64(head.generation) == uint64(old.generation) + 1
  assert bank.restore(prepared.root, policy(), ByteLimit(1000)).error == CheckpointBankError.None
proc main() =
  ## Failed/default/moved/narrowed buffers cannot alter selector or selected file; successful publication needs no re-encoding.
  for suffix in [".head", ".0", ".1"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # Test-owned reset precedes native owner acquisition.
  defer:
    for suffix in [".head", ".head.lock", ".0", ".1"]:
      var path = Prefix & suffix
      discard posix.unlink(path.toCString()) # All bank and buffer owners below retire before test-only inode removal.
  var first = detached(1)
  var second = detached(2)
  let invalid = default(PreparedCheckpoint)
  var bank = default(CheckpointBank)
  defer: discard bank.close()
  assert bank.initialize(first, ByteLimit(1000)).error == CheckpointBankError.Uninitialized
  assert bank.openCheckpointBank(Prefix) == CheckpointBankError.None
  assert bank.initialize(invalid, ByteLimit(1000)).checkpointError == CheckpointError.Uninitialized
  assert bank.initialize(first, ByteLimit(uint64(first.byteLength - 1))).checkpointError ==
      CheckpointError.LimitExceeded
  let head = bank.initialize(first, ByteLimit(uint64(first.byteLength))).value
  assert array[32, byte](head.root) == array[32, byte](first.root)
  let headBytes = readBoundedFile(Prefix & ".head", ByteLimit(1000)).value
  let slotBytes = readBoundedFile(Prefix & ".0", ByteLimit(1000)).value
  assert bank.advance(head, invalid, ByteLimit(1000)).checkpointError ==
      CheckpointError.Uninitialized
  assert bank.advance(head, second, ByteLimit(uint64(second.byteLength - 1))).checkpointError ==
      CheckpointError.LimitExceeded
  assert readBoundedFile(Prefix & ".head", ByteLimit(1000)).value == headBytes
  assert readBoundedFile(Prefix & ".0", ByteLimit(1000)).value == slotBytes
  var moved = move(second)
  assert bank.advance(head, second, ByteLimit(1000)).checkpointError ==
      CheckpointError.Uninitialized
  let advanced = bank.advance(head, moved, ByteLimit(uint64(moved.byteLength))).value
  assert advanced.slot == CheckpointSlot.Second and uint64(advanced.generation) == 1
  assert array[32, byte](advanced.root) == array[32, byte](moved.root)
  assert bank.restore(moved.root, policy(), ByteLimit(1000)).error == CheckpointBankError.None
  assert readBoundedFile(Prefix & ".0", ByteLimit(1000)).value == slotBytes
  assert first.error == CheckpointError.None and moved.error ==
      CheckpointError.None # Synchronous publication borrows rather than consumes each exclusive source buffer.
  cycle(bank, first)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(bank, first) # No original complete-map alias or per-generation byte buffer is retained by the bank.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_bank_prepared", 1000, before, after)
  assert bank.close() == CheckpointBankError.None
  assert bank.advance(advanced, first, ByteLimit(1000)).error == CheckpointBankError.Uninitialized
  echo "PASS prepared bank publication: detached buffers, exact ceilings and shared durable selection"
main()
