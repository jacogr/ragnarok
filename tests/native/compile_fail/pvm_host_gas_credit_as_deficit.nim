# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compilation must distinguish executable gas credit from a terminal deficit magnitude.

import ../../../src/pvm/machine
discard MachineInfo(gasDeficit: MachineGas(1))
