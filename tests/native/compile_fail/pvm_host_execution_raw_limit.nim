# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compilation must reject a raw integer in the nominal host-dispatch budget field.

import ../../../src/pvm/step
# A typed budget holder tests the distinct domain without unrelated callback instantiation failures.
type Policy = object
  calls: HostCallLimit
discard Policy(calls: 1'u64)
