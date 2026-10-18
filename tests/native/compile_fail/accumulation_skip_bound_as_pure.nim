# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compilation fixture preventing accidental bound/pure service API interchange.
## Block-bound provenance must use its dedicated adapter rather than an implicit representation conversion.

import ../../../src/state/[accumulation_skip, accumulation_service]
discard finishUninvokedAccumulation(default(BlockAccumulationService))
