# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A telemetry descriptor has one owner even when wrapped in fixed queue/configuration storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/telemetry/client
var original = default(Client)
var duplicate = original
original.close()
duplicate.close()
