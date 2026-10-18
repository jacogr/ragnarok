# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Rejected misuse: primitive result state is private and exposed only through read-only accessors.
import ../../../src/codec/[natural, fixed_unsigned]
discard FixedEncodeResult(success: true, encodedValue: EncodedFixed(len: 0))
