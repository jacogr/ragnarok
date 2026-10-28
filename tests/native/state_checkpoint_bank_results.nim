# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bank payload and inner reasons require their exact successful/failed alternative; native owners require close.

import std/assertions
import std/cmdline
import std/posix/posix
import ../../src/state/checkpoint_bank as state_checkpoint_bank
import ../../src/state/checkpoint_head as state_checkpoint_head
import ../../src/state/checkpoint_file as state_checkpoint_file
import ../../src/state/store as state_store
import ../../src/lib/atomic_file as lib_atomic_file
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_trie as codec_state_trie

proc policy(): StateStoreLimits =
  ## Empty maps need no value/node budget and no unrelated protocol state.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(0), perValue: ByteLimit(0),
    totalValueBytes: ByteLimit(0), nodes: TrieNodeLimit(0)), writes: ElementLimit(0),
        writeValueBytes: ByteLimit(0))
proc forgotten() =
  ## Composite destruction must enforce the live child's explicit retirement obligation.
  var bank = default(CheckpointBank)
  assert bank.openCheckpointBank("build/state-bank-forgotten") == CheckpointBankError.None
proc main() =
  ## A genuine on-disk head and complete-map control prove the same APIs used by each rejected extraction.
  let mode = paramStr(1)
  if mode == "unclosed":
    forgotten() # The bank owner may not disappear with an active native lock.
  else:
    let prefix = "build/state-bank-results"
    defer:
      for suffix in [".head", ".head.lock", ".0"]:
        var path = prefix & suffix
        discard posix.unlink(path.toCString()) # Test-only artifacts retire after the checked native owner below.
    var bank = default(CheckpointBank)
    defer: discard bank.close()
    if mode == "default":
      discard bank.selectedHead().value # Inactive bank has no selected head.
    else:
      assert bank.openCheckpointBank(prefix) == CheckpointBankError.None
      let snapshot = newStateStore([], policy()).value.snapshot.value
      let head = newCheckpointHead(CheckpointGeneration(0), CheckpointSlot.First,
          snapshot.commitment.root)
      assert saveFullCheckpoint(prefix & ".0", snapshot, ByteLimit(1000)).error ==
          CheckpointFileError.None
      assert replaceAtomicFile(prefix & ".head", encodeCheckpointHead(head, ByteLimit(1000)).value,
          ByteLimit(1000)) == AtomicFileError.None
      assert bank.restore(snapshot.commitment.root, policy(), ByteLimit(
          1000)).value.snapshot.value.commitment.entries == 0
      if mode == "refused":
        discard bank.restore(snapshot.commitment.root, policy(), ByteLimit(
            0)).value # Ceiling failure exposes no partial state.
      elif mode == "initialize-refused":
        discard bank.initialize(snapshot, ByteLimit(
            1000)).value # Existing head cannot yield a successful second bootstrap.
      elif mode == "advance-refused":
        let stale = newCheckpointHead(CheckpointGeneration(1), head.slot, head.root)
        discard bank.advance(stale, snapshot, ByteLimit(
            1000)).value # Stale local metadata cannot extract a committed successor.
      elif mode == "head-reason":
        discard bank.selectedHead().headError # Success has no failed metadata diagnostic.
      elif mode == "state-reason":
        discard bank.restore(snapshot.commitment.root, policy(), ByteLimit(
            1000)).checkpointError # Success has no failed state diagnostic.
      elif mode == "closed":
        assert bank.close() == CheckpointBankError.None
        discard bank.selectedHead().value # Earlier success does not authorize a closed resource.
      else:
        assert mode == "positive" # The complete positive path succeeds and its defer closes the native owner.
main()
