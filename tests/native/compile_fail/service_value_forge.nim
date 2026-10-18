# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot mutate retained storage or forge guarded service-value success.
import ../../../src/codec/state_service_values
discard ServiceValueResult[int](status: ServiceValueError.None, completed: 0)
