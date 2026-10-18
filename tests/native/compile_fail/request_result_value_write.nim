# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot forge success or mutate read-only request results.
import ../../../src/codec/state_requests
var parsed = default(RequestResult[int])
parsed.value = 0
