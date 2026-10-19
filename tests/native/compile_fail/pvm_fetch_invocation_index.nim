# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Protocol service identities cannot substitute for prepared service-group ordinals.

# @@Verification={"group": "nominal", "expected": "got: ServiceIndex but wanted: InvocationServiceIndex"}

import ../../../src/state/accumulation_inputs
import ../../../src/codec/composite

## Test-only holder isolates nominal assignment from procedure-overload diagnostics.
type Selection = object
  index: InvocationServiceIndex

discard Selection(index: ServiceIndex(0))
