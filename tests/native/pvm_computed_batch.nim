# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized batch refusals retain genuine complete-context positive controls.

import std/[assertions, cmdline]
import ../../src/state/computed/[batch as computed_batch, envelope as computed_envelope]
import ../../src/codec/bounded
import ../support/pvm_computed_batch

proc expect[T](outcome: ComputedBatchResult[T], reason: ComputedBatchError) =
  ## Confirm the exact selected refusal before deliberately attempting absent payload extraction.
  assert outcome.error == reason, "batch runtime control"
let sources = batchEnvelopes()
let broad = batchLimits()
let done = prepareComputedBatch(sources, broad)
expect(done, ComputedBatchError.None)
assert done.value.computedBatchInfo.value.reporters == 6
let missing = default(ComputedBatchResult[ComputedGuaranteeBatch])
let invalid = prepareComputedBatch([default(ComputedGuaranteeEnvelope)], broad)
expect(invalid, ComputedBatchError.InvalidSource)
let order = prepareComputedBatch([sources[1], sources[0]], broad)
expect(order, ComputedBatchError.NonCanonical)
var cap = broad
cap.bytes = ByteLimit(done.value.computedBatchInfo.value.bytes-1)
let wire = prepareComputedBatch(sources, cap)
expect(wire, ComputedBatchError.LimitExceeded)
cap = broad
cap.reporters = ElementLimit(5)
let reporters = prepareComputedBatch(sources, cap)
expect(reporters, ComputedBatchError.LimitExceeded)
case paramStr(1)
of "default": discard missing.value # Default has no completed batch.
of "source": discard invalid.value # No default certificate has authority.
of "order": discard order.value # Out-of-order cores expose no prefix.
of "wire": discard wire.value # Complete wire cap refuses before output allocation.
of "reporters": discard reporters.value # Unique union cap refuses without a partial set.
of "index": discard done.value.computedBatchSourceAt(ComputedBatchIndex(2)).value # No third source.
of "key-index": discard done.value.computedBatchReporterAt(ComputedBatchReporterIndex(
    6)).value # No seventh reporter.
of "info": discard default(ComputedGuaranteeBatch).computedBatchInfo.value # No copied metadata.
of "bytes": discard default(ComputedGuaranteeBatch).computedBatchBytes.value # No canonical encoding.
of "owner": discard default(ComputedGuaranteeBatch).computedBatchSourceAt(ComputedBatchIndex(
    0)).value # No original sources.
else: discard default(ComputedGuaranteeBatch).computedBatchReporterAt(ComputedBatchReporterIndex(
    0)).value # No reporter set.
