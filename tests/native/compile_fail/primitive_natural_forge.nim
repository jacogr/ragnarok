# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Rejected misuse: primitive result state is private and exposed only through read-only
## accessors.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/[natural, fixed_unsigned]
discard DecodeResult(success: true, decodedValue: JamNatural(0), byteConsumed: 1)
