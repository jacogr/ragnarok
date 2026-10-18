# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Scalar owners do not expose native pointers or mutable ARC storage.
import ../../../src/bandersnatch/bandersnatch
let key = default(BsKey)
discard key.state
