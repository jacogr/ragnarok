# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External safe code cannot read or retag private transition storage.
import ../../../src/state/disputes
var outcome = default(DisputesResult[DisputesPlan])
discard outcome.completed # Must fail privacy checking before generating native code.
