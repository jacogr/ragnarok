# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Accumulation and state-root commitments are separate nominal protocol domains.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "AccumulationRoot", "early": ["correctHistoryParent(", "[2] expected: HistoryStateRoot but got: AccumulationRoot"]}

import ../../../src/state/history
import ../../../src/codec/state_history
discard correctHistoryParent(default(HistorySnapshot), default(AccumulationRoot), default(HistoryConfig))
