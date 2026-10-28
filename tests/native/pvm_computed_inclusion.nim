# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized inclusion refusals use a genuinely authenticated guarantee-bearing positive control.

import std/assertions
import std/cmdline
import ../../src/state/computed_inclusion as state_computed_inclusion
import ../../src/state/computed_batch as state_computed_batch
import ../../src/codec/bounded as codec_bounded
import ../support/pvm_computed_inclusion
import ../support/pvm_computed_batch

proc expect[T](outcome: ComputedInclusionResult[T], reason: ComputedInclusionError) =
  ## Confirm exact alternative before deliberately extracting missing application data.
  assert outcome.error == reason, "inclusion runtime control"
let source = inclusionFixture()
let done = bindComputedInclusion(source, ByteLimit(100000))
expect(done, ComputedInclusionError.None)
let absent = prepareComputedBatch(batchEnvelopes(), batchLimits()).value
let mismatch = bindComputedInclusion(absent, ByteLimit(100000))
expect(mismatch, ComputedInclusionError.GuaranteeMismatch)
let invalid = bindComputedInclusion(default(ComputedGuaranteeBatch), ByteLimit(100000))
expect(invalid, ComputedInclusionError.InvalidSource)
let short = bindComputedInclusion(source, ByteLimit(source.computedBatchInfo.value.bytes-1))
expect(short, ComputedInclusionError.LimitExceeded)
let missing = default(ComputedInclusionResult[IncludedComputedGuarantees])
case paramStr(1)
of "default": discard missing.value # Default has no included source.
of "source": discard invalid.value # Loose/default batches supply no original candidate.
of "mismatch": discard mismatch.value # Missing actual guarantees expose no prefix.
of "limit": discard short.value # Refused copies publish no inclusion certificate.
of "owner": discard default(IncludedComputedGuarantees).computedInclusionSource.value # No retained batch.
of "stage": discard default(IncludedComputedGuarantees).computedInclusionStage.value # No authenticated prefix.
else: discard default(IncludedComputedGuarantees).computedInclusionComponent.value # No candidate component.
