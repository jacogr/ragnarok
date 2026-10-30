# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Session callers cannot expose private stream owners, buffers or callback entry points.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "frameExtent"}

import "../../../src/jamnp-s/session"
discard session.frameExtent
