# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Direct scalar helpers reject a statically invalid width before generating executable code.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "schemas", "expected": "9"}

import ../../../src/codec/collections
discard scalarMinimum(CollectionUInt[9])
