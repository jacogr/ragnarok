# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Setup owners do not expose native pointers or mutable ARC storage.
import ../../../src/bandersnatch/bandersnatch
let setup = default(BsSetup)
discard setup.state
