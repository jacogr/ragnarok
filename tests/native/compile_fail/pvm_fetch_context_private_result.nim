# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject access to private immutable fetch context storage.

import ../../../src/pvm/host_fetch
let captured = default(FetchContextResult)
discard captured.completed
