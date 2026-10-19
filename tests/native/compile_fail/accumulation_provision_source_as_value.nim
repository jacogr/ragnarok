# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A per-context provision ordinal cannot select a retained union source.

import ../../../src/state/[accumulation_provisions, accumulation_effects]
var plan: PreparedAccumulationProvisions
discard provisionSourceAt(plan, AccumulationProvisionIndex(0))
