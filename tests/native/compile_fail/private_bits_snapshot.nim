# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot mutate immutable private packed bytes.
import ../../../src/codec/bitstrings
var owner: OwnedBits
discard owner.data
