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

proc checkInspectionRefusal[T](outcome: ExportInspectionResult[T],
    expected: RefinementExportError) =
  ## Prove the runtime refusal before forbidden extraction without exporting a contradictory static postcondition.
  assert outcome.error == expected

let empty = default(RefinementExports)
let missing = default(RefinementExportResult)
let memory = captureMemory([], PageLimit(0)).value
let refused = exportResponse(empty, MachineGas(3521), default(RegisterFile), memory,
  ExportLimits(items: ElementLimit(1), bytes: ByteLimit(4104)))
checkRefusal(refused)
let valid = captureRefinementExports(ExportOffset(0))
assert valid.count.error == RefinementExportError.None and uint64(valid.count.value) == 0
case paramStr(1)
of "default-result":
  # An uninitialized result has no completed response/successor pair.
  discard missing.value
of "refused-result":
  # A local refusal cannot fabricate a successful export transition.
  discard refused.value
of "default-count":
  # Missing owners return a typed refusal; only forbidden extraction violates the result contract.
  let observed = empty.count
  checkInspectionRefusal(observed, RefinementExportError.InvalidContext)
  discard observed.value
of "default-segment":
  # Inspecting a missing owner is safe and never exposes segment bytes.
  let observed = empty.segment(ExportCount(0))
  checkInspectionRefusal(observed, RefinementExportError.InvalidContext)
  discard observed.value
else:
  # Full-width out-of-range indices fail before narrowing or array access.
  var index = ExportCount(0)
  if paramStr(2) == "huge": index = ExportCount(high(
      uint64)) # Runtime-selected width avoids a statically rejected constant call.
  let observed = valid.segment(index)
  checkInspectionRefusal(observed, RefinementExportError.InvalidIndex)
  discard observed.value
