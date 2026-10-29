# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "got: ByteLimit but wanted: ElementLimit"}

## Explicit-input coverage cannot alias byte counts, protocol IDs or completed block authority.
import ../../../src/state/accumulation/[coverage as accumulation_coverage,
    execution as accumulation_execution]
import ../../../src/codec/bounded
import ../../../src/codec/state/accounts as state_accounts
discard AccumulationCoverageLimits(services: ByteLimit(1))
