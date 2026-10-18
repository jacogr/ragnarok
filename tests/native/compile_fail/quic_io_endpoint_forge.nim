# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw descriptor/open metadata must not be forgeable by callers.
import ../../../src/quic/io
discard UdpEndpoint(opened: true)
