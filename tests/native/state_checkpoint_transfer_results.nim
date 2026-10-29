# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exclusive prepared owners cannot expose a root or size from default, moved or refused alternatives.

import std/[assertions, cmdline]
import ../../src/state/checkpoint/transfer as checkpoint_transfer
import ../../src/state/[checkpoint, store]
import ../../src/codec/bounded
import ../../src/codec/state/trie as state_trie

proc main() =
  ## Real initialized empty-map preparation validates the same accessors exercised by negative cases.
  let mode = paramStr(1)
  let limits = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(0), perValue: ByteLimit(0),
    totalValueBytes: ByteLimit(0), nodes: TrieNodeLimit(0)), writes: ElementLimit(0),
        writeValueBytes: ByteLimit(0))
  let snapshot = newStateStore([], limits).value.snapshot.value
  var prepared = prepareFullCheckpoint(snapshot, ByteLimit(1000))
  assert prepared.error == CheckpointError.None and prepared.byteLength > 0
  if mode == "default-root":
    let absent = default(PreparedCheckpoint)
    discard absent.root # Default bytes do not establish a usable commitment.
  elif mode == "refused-size":
    let refused = prepareFullCheckpoint(snapshot, ByteLimit(0))
    discard refused.byteLength # A refused prefix has no successful extent.
  elif mode == "moved-root":
    let transferred = move(prepared)
    assert transferred.error == CheckpointError.None
    discard prepared.root # Moving transfers all authority and resets the source owner.
  else:
    assert mode == "positive" and array[32, byte](prepared.root) == default(array[32,
        byte]) # A genuine initialized empty-map root is allowed.
main()
