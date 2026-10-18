# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject bypasses of private ownership/results or nominal address/resource domains.
import ../../../src/pvm/machine
discard load(default(Memory), PageIndex(16), AccessWidth(1))
