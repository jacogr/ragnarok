# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler rejection fixture protecting private service-context storage and nominal argument domains.
## Its top-level access or call must fail semantic compilation rather than forge validated context.

# @@Verification={"group": "nominal", "expected": "InvocationServiceIndex", "early": ["prepareBlockAccumulationService(", "[2] expected: InvocationServiceIndex but got: ServiceIndex"]}

import ../../../src/state/accumulation/[service as accumulation_service,
    round as accumulation_round, inputs as accumulation_inputs]
import ../../../src/codec/[bounded, composite]
discard prepareBlockAccumulationService(default(BlockAccumulationRound), ServiceIndex(0), default(AccumulationServiceConfig))
