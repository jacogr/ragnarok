# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot forge completed native imports.
import ../../../src/bandersnatch/bandersnatch
discard BsResult[BsKey](status: BsError.None, completed: default(BsKey))
