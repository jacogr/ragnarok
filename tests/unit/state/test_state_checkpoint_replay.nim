# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Checkpoint serialization/restoration preserves all fourteen independently pinned published complete maps.

import std/[assertions, syncio]
import ../../../src/state/checkpoint
import ../../../src/state/checkpoint/transfer as checkpoint_transfer
import ../../../src/state/store
import ../../../src/codec/state/trie as state_trie
import ../../../src/codec/bounded
import ../../support/published_state

proc replay(expected: Mapping) =
  ## Original fixture roots and every original key/value are independent expectations, never checkpoint-derived goldens.
  let limits = policy(expected, expected)
  let source = newStateStore(expected.entries, limits).value.snapshot.value
  matches(source, expected)
  let encoded = encodeFullCheckpoint(source, ByteLimit(high(uint64))).value
  let exact = ByteLimit(uint64(encoded.len))
  assert encodeFullCheckpoint(source, exact).value == encoded
  assert encodeFullCheckpoint(source, ByteLimit(uint64(encoded.len - 1))).error ==
      CheckpointError.LimitExceeded
  let restored = decodeFullCheckpoint(encoded, expected.root, limits, exact)
  assert restored.error == CheckpointError.None
  matches(restored.value.snapshot.value, expected)
  assert encodeFullCheckpoint(restored.value.snapshot.value, exact).value == encoded
  assert decodeFullCheckpoint(encoded, expected.root, limits, ByteLimit(uint64(encoded.len -
      1))).error == CheckpointError.LimitExceeded
  var wrong = array[32, byte](expected.root)
  wrong[0] = wrong[0] xor 1
  assert decodeFullCheckpoint(encoded, StateRoot(wrong), limits, exact).error ==
      CheckpointError.RootMismatch
  var short = limits
  assert expected.entries.len > 0
  short.trie.items = ElementLimit(expected.entries.len - 1)
  assert decodeFullCheckpoint(encoded, expected.root, short, exact).error ==
      CheckpointError.LimitExceeded
  var prepared = prepareFullCheckpoint(source, exact)
  assert prepared.error == CheckpointError.None and uint64(prepared.byteLength) == uint64(encoded.len)
  assert array[32, byte](prepared.root) == array[32, byte](expected.root)
proc main() {.raises.} =
  ## The existing provider checks pinned blobs and independent roots before either native consumer receives trusted text.
  let mappings = publishedMappings()
  for expected in mappings:
    replay(expected) # All fourteen original complete maps remain individually checked even when roots repeat.
  echo "PASS checkpoint replay: fourteen published maps, exact bytes, independent roots and resource refusals"
try:
  main() # Fixture/crypto failures must not yield a successful empty run.
except:
  quit(2)
