# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit tiny structural and full-map ceilings for published TraceStep wire witnesses.
import ../../src/state/trace_step as state_trace_step
import ../../src/state/store as state_store
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/composite as codec_composite
import ../../src/codec/tickets as codec_tickets
import ../../src/codec/assurances as codec_assurances
import ../../src/codec/header as codec_header
import ../../src/codec/state_trie as codec_state_trie
proc traceStepTestLimits*(): TraceStepLimits =
  ## Resource caps are independent of untrusted counts, roots and any current service metadata.
  TraceStepLimits(bytes: ByteLimit(8388608),
      frame: FrameConfig(cores: CoreCount(2), validators: ValidatorCount(6), epochSlots: EpochSlots(
          12), ticketLimit: TicketLimit(3), maxBytes: ByteLimit(2097152),
          preimages: PreimageLimits(items: ElementLimit(10000), perBlob: ByteLimit(2097152),
              totalBlobBytes: ByteLimit(4194304))),
      state: StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4096), perValue: ByteLimit(
          2097152), totalValueBytes: ByteLimit(4194304), nodes: TrieNodeLimit(100000)),
          writes: ElementLimit(4096), writeValueBytes: ByteLimit(4194304)))
