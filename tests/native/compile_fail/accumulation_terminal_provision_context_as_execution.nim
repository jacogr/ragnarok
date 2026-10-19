# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulationDispatchResult", "early": ["prepareTerminalAccumulationProvisions(", "[1] expected: openArray but got: array[0..0, AccumulationEffectContext]"]}

## Caller-selected effect contexts cannot stand in for completed execution provenance.

import ../../../src/state/[accumulation_terminal_provisions, accumulation_provisions, accumulation_effects]
import ../../../src/codec/header
var sources: array[1, AccumulationEffectContext]
discard prepareTerminalAccumulationProvisions(sources, HeaderSlot(128), default(AccumulationProvisionUnionLimits))
