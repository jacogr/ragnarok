# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit current Tiny structural domains and bounded opaque maps for fuzzer wire witnesses.
import ./trace_step_context
import ../../src/state/fuzz/protocol as fuzz_protocol
import ../../src/codec/bounded
proc fuzzProtocolTestLimits*(): FuzzLimits =
  ## Codec ceilings are caller policy; peer declarations and historical session versions cannot widen them.
  let trace = traceStepTestLimits()
  FuzzLimits(bytes: trace.bytes, text: ByteLimit(4096), state: trace.state, frame: trace.frame)
