# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler rejection fixture protecting private bootstrap ownership and nominal scalar/resource domains.
## The top-level access or call must fail semantic compilation before any payload can be used.

## Verification: {"group": "nominal", "expected": "AccumulationArgumentCount", "early": ["accumulationArguments(", "[3] expected: AccumulationArgumentCount but got: ServiceIndex"]}

import ../../../src/state/[accumulation_invocation, store]
import ../../../src/codec/[bounded, composite, header]
discard accumulationArguments(HeaderSlot(0), ServiceIndex(0), ServiceIndex(0))
