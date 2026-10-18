# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A known failure has no extractable configuration snapshot.
import std/assertions
import ../../../src/chain/parameters
let decoded = decodeParameters([])
assert not decoded.ok
discard decoded.value
