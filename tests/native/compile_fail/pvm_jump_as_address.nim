# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject attempts to bypass the PVM ownership/result or nominal-domain boundary.
import ../../../src/pvm/program
discard instruction(default(Program), JumpIndex(0))
