# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Accumulation and state-root commitments are separate nominal protocol domains.
import ../../../src/state/history
import ../../../src/codec/state_history
discard correctHistoryParent(default(HistorySnapshot), default(AccumulationRoot), default(HistoryConfig))
