# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compatibility import for completed reentry execution; preparation and completion share private ownership in accumulation_reentry.
## Preserves the existing guarded completion API without exposing raw construction of recursive certificates.

import ../reentry as accumulation_reentry
export AccumulationReentryExecutionInfo, AccumulationReentryExecutionError,
  CompletedAccumulationReentry, AccumulationReentryExecutionResult,
  error, value, batchFailure, executionInfo, executionGasAt, executionReentry, executionBatch,
  completeAccumulationReentry
