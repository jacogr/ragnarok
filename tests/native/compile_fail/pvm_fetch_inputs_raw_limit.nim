# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw byte counts cannot silently become external-input capture domains.

# @@Verification={"group": "nominal", "expected": "got: uint64 but wanted: FetchInputLimit"}

import ../../../src/pvm/host/fetch as host_fetch

# Test-only holder isolates nominal budget assignment from callback/procedure overload checking.
type Input = object
  limit: FetchInputLimit

discard Input(limit: 1'u64)
