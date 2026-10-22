# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "got: ByteLimit but wanted: ElementLimit"}

## Explicit-input coverage cannot alias byte counts, protocol IDs or completed block authority.
import ../../../src/state/[accumulation_coverage, accumulation_execution]
import ../../../src/codec/[bounded, state_accounts]
discard AccumulationCoverageLimits(services: ByteLimit(1))
