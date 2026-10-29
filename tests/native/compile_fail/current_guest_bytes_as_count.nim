# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "got: ByteLimit but wanted: ElementLimit"}

## Guest work counts cannot alias payload bytes or protocol gas.
import ../../../src/state/accumulation/guest_runner as accumulation_guest_runner
import ../../../src/codec/[bounded, composite]
discard AccumulationGuestLimits(services: ByteLimit(1))
