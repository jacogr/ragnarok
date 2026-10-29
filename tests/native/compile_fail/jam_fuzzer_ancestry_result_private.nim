# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A failed ancestry lookup cannot expose a fabricated successful ordinal or context.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/state/fuzz/ancestry as fuzz_ancestry
let outcome = default(FuzzAncestryResult[FuzzAncestry])
discard outcome.completed
