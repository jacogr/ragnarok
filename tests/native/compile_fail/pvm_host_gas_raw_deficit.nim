# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compilation must reject raw integers in the nominal terminal gas-deficit field.

import ../../../src/pvm/machine
discard MachineInfo(gasDeficit: 1'u64)
