# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## An application cannot forge the identity of an outstanding fuzzer request.
import ../../../src/state/fuzz_session as state_fuzz_session
let ticket = default(FuzzRequest)
discard ticket.data
