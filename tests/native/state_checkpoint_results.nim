# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and refused checkpoint results reject extraction; the same binary admits real success.

import std/cmdline
import std/assertions
import ../../src/state/checkpoint as state_checkpoint
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_trie as codec_state_trie

let mode = paramStr(1)
if mode == "root-refused":
  let snapshot = newStateStore([], default(StateStoreLimits)).value.snapshot.value
  let bytes = encodeFullCheckpoint(snapshot, ByteLimit(100)).value
  var root = default(array[32, byte])
  root[0] = 1
  discard decodeFullCheckpoint(bytes, StateRoot(root), default(StateStoreLimits), ByteLimit(
      100)).value # A valid foreign complete root has no payload authority.
elif mode == "decode-default":
  let outcome = default(CheckpointResult[StateStore])
  discard outcome.value # Generic restored stores have the same guarded absence contract.
elif mode == "decode-refused":
  discard decodeFullCheckpoint([], default(StateStoreLimits), ByteLimit(
      100)).value # A malformed document cannot expose a partial map.
elif mode == "default":
  let outcome = default(CheckpointResult[seq[byte]])
  discard outcome.value # Default construction never authorizes bytes.
else:
  let snapshot = newStateStore([], default(StateStoreLimits)).value.snapshot.value
  if mode == "positive":
    assert encodeFullCheckpoint(snapshot, ByteLimit(100)).value.len >
        0 # A real initialized empty map is extractable.
  else:
    discard encodeFullCheckpoint(snapshot, ByteLimit(
        0)).value # A genuine size refusal has no partial header payload.
