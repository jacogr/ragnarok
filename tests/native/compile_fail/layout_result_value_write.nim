# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, retag or mutate state-layout result/metadata storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "value"}

import ../../../src/codec/state_layout
var value = default(StateLayoutResult[StateKey])
value.value = default(StateKey)
