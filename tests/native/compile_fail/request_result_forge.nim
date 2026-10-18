# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot forge success or mutate read-only request results.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/state_requests
discard RequestResult[int](status: RequestError.None, completed: 0)
