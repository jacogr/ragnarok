# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real durable bank generations recover independently pinned complete maps across close/reopen and selected-data corruption.

import std/[assertions, syncio]
import std/posix/posix
import ../../../src/state/checkpoint/[bank as checkpoint_bank, head as checkpoint_head,
    transfer as checkpoint_transfer]
import ../../../src/state/[checkpoint, store]
import ../../../src/lib/atomic/file as atomic_file
import ../../../src/codec/state/trie as state_trie
import ../../../src/codec/bounded
import ../../support/published_state

const Prefix = "state-bank-replay"
proc clearFiles() =
  ## Only known suite-owned canonical files and the stable lock are removed after every descriptor retires.
  for suffix in [".head", ".head.lock", ".0", ".1"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # No live bank or worker owns this namespace at cleanup boundaries.
proc replay(before, after: Mapping) =
  ## Published pre/post roots authorize recovery independently from all locally written selectors.
  clearFiles()
  defer: clearFiles()
  let limits = policy(before, after)
  let prior = newStateStore(before.entries, limits).value.snapshot.value
  let posterior = newStateStore(after.entries, limits).value.snapshot.value
  let priorBytes = encodeFullCheckpoint(prior, ByteLimit(high(uint64))).value
  let nextBytes = encodeFullCheckpoint(posterior, ByteLimit(high(uint64))).value
  let maximum = ByteLimit(uint64(max(priorBytes.len, nextBytes.len)))
  var bank = default(CheckpointBank)
  defer: discard bank.close()
  assert bank.openCheckpointBank(Prefix) == CheckpointBankError.None
  var first = prepareFullCheckpoint(prior, maximum)
  let initial = bank.initialize(first, maximum).value
  assert initial.slot == CheckpointSlot.First and uint64(initial.generation) == 0
  matches(bank.restore(before.root, limits, maximum).value.snapshot.value, before)
  assert bank.close() == CheckpointBankError.None
  assert bank.openCheckpointBank(Prefix) == CheckpointBankError.None
  var second = prepareFullCheckpoint(posterior, maximum)
  let advanced = bank.advance(initial, second, maximum).value
  assert advanced.slot == CheckpointSlot.Second and uint64(advanced.generation) == 1
  assert readBoundedFile(Prefix & ".0", maximum).value == priorBytes
  assert readBoundedFile(Prefix & ".1", maximum).value == nextBytes
  let selected = readBoundedFile(Prefix & ".head", ByteLimit(CheckpointHeadBytes)).value
  assert bank.advance(initial, first, maximum).error == CheckpointBankError.StaleHead
  assert readBoundedFile(Prefix & ".head", ByteLimit(CheckpointHeadBytes)).value == selected
  assert bank.close() == CheckpointBankError.None
  assert bank.openCheckpointBank(Prefix) == CheckpointBankError.None
  matches(bank.restore(after.root, limits, maximum).value.snapshot.value, after)
  assert array[32, byte](bank.verify(after.root, limits, maximum).value.root) == array[32, byte](after.root)
  var damaged = nextBytes
  damaged[damaged.high] = damaged[damaged.high] xor 1
  assert replaceAtomicFile(Prefix & ".1", damaged, maximum) == AtomicFileError.None
  let refused = bank.restore(after.root, limits, maximum)
  assert refused.error == CheckpointBankError.InvalidCheckpoint # An intact old generation must not replace the selected damaged complete map.
  assert bank.verify(after.root, limits, maximum).error == CheckpointBankError.InvalidCheckpoint
  assert readBoundedFile(Prefix & ".head", ByteLimit(CheckpointHeadBytes)).value == selected
  assert readBoundedFile(Prefix & ".0", maximum).value == priorBytes
  assert replaceAtomicFile(Prefix & ".1", nextBytes, maximum) == AtomicFileError.None
  matches(bank.restore(after.root, limits, maximum).value.snapshot.value, after)
  assert bank.close() == CheckpointBankError.None
proc main() {.raises.} =
  ## Existing independent fixture preparation preserves all seven source pairs and their original serialized mappings.
  let mappings = publishedMappings()
  for index in 0..<7:
    replay(mappings[2*index], mappings[2*index+1]) # Every pair crosses real close/reopen and both durable publication stages.
  echo "PASS checkpoint bank replay: seven published pairs, durable generations, restart and selected corruption"
try:
  main() # No missing or invalid fixture may be accepted as a successful empty corpus.
except:
  quit(2)
