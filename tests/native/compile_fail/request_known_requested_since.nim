# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A statically known Requested shape cannot supply an Available timestamp.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import std/assertions
import ../../../src/codec/state_requests
let history = requestedHistory()
assert history.state == RequestState.Requested
discard history.since
