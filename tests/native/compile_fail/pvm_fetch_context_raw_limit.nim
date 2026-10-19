# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject implicit raw integer assignment to the trace capture budget.

## Verification: {"group": "nominal", "expected": "got: uint64 but wanted: FetchTraceLimit"}

import ../../../src/pvm/host_fetch

# Isolate the nominal capture budget from unrelated procedure overload diagnostics.
type Input = object
  limit: FetchTraceLimit

discard Input(limit: 1'u64)
