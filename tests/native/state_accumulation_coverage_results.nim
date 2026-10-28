# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused coverage alternatives cannot expose complete rows or inactive provider owners.
import std/cmdline
import ../../src/state/accumulation_coverage as state_accumulation_coverage
import ../../src/state/accumulation_annulment as state_accumulation_annulment
import ../../src/codec/header as codec_header
let argument = paramStr(1)
let owner = default(PreparedAccumulationCoverage)
let ordinal = AccumulationCoverageIndex(0)
let refused = if argument == "default": default(AccumulationCoverageResult[PreparedAccumulationCoverage])
  else: prepareAccumulationCoverage(default(PreparedAccumulationAnnulment), [], [], HeaderSlot(0),
      default(AccumulationCoverageLimits))
case argument
of "info": discard owner.coverageInfo.value # No default empty coverage.
of "source": discard owner.coverageAnnulment.value # No substitute original/selected source.
of "row": discard owner.coverageRowAt(ordinal).value # No fabricated default execution row.
of "original": discard owner.coverageOriginalAt(ordinal).value # No fabricated executed outcome.
of "skip": discard owner.coverageSkippedAt(ordinal).value # No fabricated code-unavailable proof.
of "absent": discard owner.coverageAbsentAt(ordinal).value # No fabricated no-credit proof.
else: discard refused.value # Failure carries the reason alone.
