# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <AncestorReceiver>", "build_name": "application-ancestor-receiver-copy"}

## Duplicating a live receiver would duplicate mutable response storage and cancellation authority.
import ../../../src/app/ancestor_receiver
var original = default(AncestorReceiver)
var duplicate = original
discard original.stage
discard duplicate.stage
