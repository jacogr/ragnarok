# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "got: ByteLimit but wanted: ElementLimit"}

## Account positions and element limits cannot alias source owners or byte extents.
import ../../../src/state/[accumulation_creation_union, accumulation_annulment]
import ../../../src/codec/bounded
discard AccumulationCreationLimits(accounts: ByteLimit(1))
