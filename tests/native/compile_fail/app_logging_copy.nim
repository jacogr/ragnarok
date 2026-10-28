# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A logger owns native synchronization and a worker borrowing its stable address; it cannot duplicate.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <Logger>", "build_name": "logging-copy"}
import ../../../src/lib/logging as lib_logging
var original = default(Logger)
var duplicate = original
original.close()
duplicate.close()
