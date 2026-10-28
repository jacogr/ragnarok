# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_bootstrap_arc_release"}

## Explicit bootstrap publishes complete data before the sole selector and cannot overwrite an existing head.

import std/assertions
import std/syncio
import std/posix/posix
import ../../../src/state/checkpoint_bank as state_checkpoint_bank
import ../../../src/state/checkpoint_head as state_checkpoint_head
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/store as state_store
import ../../../src/lib/atomic_file as lib_atomic_file
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded
import ../../support/testing_arc_evidence

const Prefix = "state-checkpoint-bootstrap"
proc policy(): StateStoreLimits =
  ## Small complete maps exercise present-empty and binary values without protocol transition assumptions.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(200), nodes: TrieNodeLimit(1024)), writes: ElementLimit(4),
        writeValueBytes: ByteLimit(200))
proc clearFiles() =
  ## Explicit test-only teardown removes heads between independent bootstrap attempts; production never auto-resets.
  for suffix in [".head", ".0", ".1"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # Stable lock inode is preserved across every active-owner cycle.
proc cycle(bank: var CheckpointBank, snapshot: StateStoreSnapshot) =
  ## A complete bootstrap, guarded reinitialization refusal and restored map all retire before ARC observation.
  clearFiles()
  assert bank.initialize(snapshot, ByteLimit(1000)).error == CheckpointBankError.None
  assert bank.initialize(snapshot, ByteLimit(1000)).error == CheckpointBankError.AlreadyInitialized
  assert bank.restore(snapshot.commitment.root, policy(), ByteLimit(1000)).error ==
      CheckpointBankError.None
proc main() =
  ## Real rename refusal and malformed existing heads preserve fail-closed explicit initialization semantics.
  clearFiles()
  var slotPath = Prefix & ".0"
  var headPath = Prefix & ".head"
  var lockPath = Prefix & ".head.lock"
  defer:
    clearFiles()
    discard posix.rmdir(slotPath.toCString())
    discard posix.rmdir(headPath.toCString())
    discard posix.unlink(lockPath.toCString()) # Native bank below closes before teardown of its test-only stable inode.
  let empty = newStateStore([], policy()).value.snapshot.value
  var keyBytes = default(array[31, byte])
  keyBytes[0] = 1
  let snapshot = newStateStore([StateEntry(key: StateKey(keyBytes), value: @[0'u8, 255])], policy()).value.snapshot.value
  var bank = default(CheckpointBank)
  defer: discard bank.close()
  assert bank.initialize(snapshot, ByteLimit(1000)).error == CheckpointBankError.Uninitialized
  assert bank.openCheckpointBank(Prefix) == CheckpointBankError.None
  let invalid = bank.initialize(default(StateStoreSnapshot), ByteLimit(1000))
  assert invalid.error == CheckpointBankError.InvalidCheckpoint and invalid.checkpointError ==
      CheckpointError.Uninitialized
  assert bank.initialize(snapshot, ByteLimit(0)).checkpointError == CheckpointError.LimitExceeded
  assert bank.selectedHead().error == CheckpointBankError.IoFailure
  assert posix.mkdir(slotPath.toCString(), Mode(0o700)) == 0
  assert bank.initialize(snapshot, ByteLimit(1000)).error == CheckpointBankError.IoFailure
  assert bank.selectedHead().error == CheckpointBankError.IoFailure # A real staged-file rename failure cannot publish a selector.
  assert posix.rmdir(slotPath.toCString()) == 0
  let initialized = bank.initialize(snapshot, ByteLimit(1000)).value
  assert uint64(initialized.generation) == 0 and initialized.slot == CheckpointSlot.First
  assert array[32, byte](initialized.root) == array[32, byte](snapshot.commitment.root)
  let headBytes = readBoundedFile(headPath, ByteLimit(CheckpointHeadBytes)).value
  let slotBytes = readBoundedFile(slotPath, ByteLimit(1000)).value
  assert bank.restore(snapshot.commitment.root, policy(), ByteLimit(1000)).error ==
      CheckpointBankError.None
  assert bank.initialize(empty, ByteLimit(1000)).error == CheckpointBankError.AlreadyInitialized
  assert readBoundedFile(headPath, ByteLimit(CheckpointHeadBytes)).value == headBytes
  assert readBoundedFile(slotPath, ByteLimit(1000)).value ==
      slotBytes # A different complete source cannot replace existing committed data.
  clearFiles()
  assert replaceAtomicFile(headPath, [7'u8], ByteLimit(1)) == AtomicFileError.None
  assert bank.initialize(snapshot, ByteLimit(1000)).error == CheckpointBankError.AlreadyInitialized
  assert readBoundedFile(headPath, ByteLimit(1)).value == @[
      7'u8] # Malformed selectors require explicit recovery, never bootstrap replacement.
  clearFiles()
  assert posix.mkdir(headPath.toCString(), Mode(0o700)) == 0
  assert bank.initialize(snapshot, ByteLimit(1000)).error == CheckpointBankError.AlreadyInitialized
  assert posix.rmdir(headPath.toCString()) == 0
  cycle(bank, snapshot)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(bank, snapshot) # Synced slot/selector publication and refusal/restoration release host-owned temporaries.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_bootstrap", 1000, before, after)
  assert bank.close() == CheckpointBankError.None
  assert bank.initialize(snapshot, ByteLimit(1000)).error == CheckpointBankError.Uninitialized
  echo "PASS checkpoint bootstrap: durable slot before selector, explicit absence and no head replacement"
main()
