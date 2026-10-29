# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized probes reject default/refused results and invalid immutable export access.

import std/[assertions, cmdline]
import ../../src/pvm/[refinement_exports, machine]
import ../../src/codec/bounded
import ../../src/codec/work/digest as work_digest

proc checkRefusal(outcome: RefinementExportResult) =
  ## Positive control confirms missing invocation exports before forbidden extraction.
  assert outcome.error == RefinementExportError.InvalidContext

let empty = default(RefinementExports)
let missing = default(RefinementExportResult)
let memory = captureMemory([], PageLimit(0)).value
let refused = exportResponse(empty, MachineGas(3521), default(RegisterFile), memory,
  ExportLimits(items: ElementLimit(1), bytes: ByteLimit(4104)))
checkRefusal(refused)
let valid = captureRefinementExports(ExportOffset(0))
assert uint64(valid.count) == 0
case paramStr(1)
of "default-result":
  # An uninitialized result has no completed response/successor pair.
  discard missing.value
of "refused-result":
  # A local refusal cannot fabricate a successful export transition.
  discard refused.value
of "default-count":
  # Missing owners cannot masquerade as an empty sequence.
  discard empty.count
of "default-segment":
  # Missing owners never expose segment bytes.
  discard empty.segment(ExportCount(0))
else:
  # Full-width out-of-range indices fail before narrowing or array access.
  var index = ExportCount(0)
  if paramStr(2) == "huge": index = ExportCount(high(
      uint64)) # Runtime-selected width avoids a statically rejected constant call.
  discard valid.segment(index)
