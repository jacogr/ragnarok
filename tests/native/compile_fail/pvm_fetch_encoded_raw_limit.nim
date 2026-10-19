# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw byte counts cannot silently become encoded-package snapshot resource budgets.

import ../../../src/pvm/host_fetch

# Test-only holder isolates nominal budget assignment from callback/procedure overload checking.
type Input = object
  limit: FetchEncodingLimit

discard Input(limit: 1'u64)
