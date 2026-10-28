# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed fuzz startup cannot expose a partially selected successful socket/backend configuration.
# @@Verification={"group": "privacy", "expected": "config"}
import ../../../src/app/fuzz_target as app_fuzz_target
let outcome = default(FuzzTargetResult)
discard outcome.config
