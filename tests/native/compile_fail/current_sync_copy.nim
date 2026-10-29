# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A continuous host cannot duplicate stable callbacks or canonical receipt ownership.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <CurrentSync>", "build_name": "current-sync-copy"}
import ../../../src/quic/current_sync
var original = default(CurrentSync)
var duplicate = original
discard original.progress
discard duplicate.progress
