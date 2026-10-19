# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Payload extraction is bound to its owner; a second source pool is not part of the API.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "copyOwnedBlob"}

import ../../../src/codec/owned
var frame: OwnedFrame
var wrongPool, output: array[2, byte]
discard copyOwnedBlob(frame, wrongPool, 0, output)
