# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A proven absent peak must not expose a hash, even before runtime checking.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "contracts", "expected": "peak.isPresent"}

import std/assertions
import ../../../src/codec/state_history
let peak = absentHistoryPeak()
assert not peak.present
discard peak.hash
