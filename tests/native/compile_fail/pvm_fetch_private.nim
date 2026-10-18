# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fetch response storage must remain private to prevent unchecked payload extraction.

import ../../../src/pvm/host_fetch
let reply = default(FetchResult)
discard reply.completed
