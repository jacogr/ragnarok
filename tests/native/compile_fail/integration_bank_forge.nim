# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Integration callers cannot forge success or mutate private snapshot/bank storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/quic/integration
import ../../../src/codec/owned
discard IntegrationBank(data: nil)
