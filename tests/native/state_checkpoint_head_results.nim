# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Checked default/failed head extraction cannot fabricate initialized selection metadata.

import std/[assertions, cmdline]
import ../../src/state/checkpoint/head as checkpoint_head
import ../../src/codec/state/trie as state_trie
import ../../src/codec/bounded

proc main() =
  ## The real round-trip positive control precedes independent default/result misuse alternatives.
  let mode = paramStr(1)
  let head = newCheckpointHead(CheckpointGeneration(0), CheckpointSlot.First, default(StateRoot))
  let bytes = encodeCheckpointHead(head, ByteLimit(1000)).value
  assert decodeCheckpointHead(bytes, ByteLimit(1000)).value.ready
  if mode == "default":
    let absent = default(CheckpointHeadResult[CheckpointHead])
    discard absent.value # Default result is never successful.
  elif mode == "encode-refused":
    discard encodeCheckpointHead(head, ByteLimit(0)).value # A failed allocation ceiling has no prefix.
  elif mode == "decode-refused":
    discard decodeCheckpointHead([], ByteLimit(1000)).value # A short header cannot be extracted.
  elif mode == "exhausted":
    let last = newCheckpointHead(CheckpointGeneration(high(uint64)), CheckpointSlot.First, default(StateRoot))
    discard nextCheckpointHead(last, default(StateRoot)).value # Exhaustion has no wrapped successor.
  elif mode == "generation":
    discard default(CheckpointHead).generation # Default zero bits do not establish initialization.
  elif mode == "slot":
    discard default(CheckpointHead).slot # No default slot is authorized.
  elif mode == "root":
    discard default(CheckpointHead).root # No default complete-root claim is authorized.
  else:
    assert mode == "positive" and uint64(head.generation) ==
        0 # Genuine successful zero generation is distinct from defaults.
main()
