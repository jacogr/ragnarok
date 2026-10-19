# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject access to private immutable fetch context storage.

## Verification: {"group": "privacy", "expected": "data"}

import ../../../src/pvm/host_fetch
let captured = default(FetchContext)
discard captured.data
