# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw descriptor/open metadata must not be forgeable by callers.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "opened"}

import ../../../src/quic/io
discard UdpEndpoint(opened: true)
