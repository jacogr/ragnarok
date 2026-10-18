# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot mutate retained storage or forge guarded service-value success.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/state_service_values
var parsed = default(ServiceValueResult[int])
parsed.value = 0
