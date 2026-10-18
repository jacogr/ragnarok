# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot forge or read private availability transition storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/state/availability
var outcome = default(AvailabilityTransitionResult[AvailabilityPlan])
discard outcome.status # Must fail before native generation.
