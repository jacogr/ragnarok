# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and refused checkpoint results reject extraction; the same binary admits real success.

import std/[cmdline, assertions]
import ../../src/state/[checkpoint, store]
import ../../src/codec/bounded

let mode = paramStr(1)
if mode == "default":
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
