# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Direct scalar helpers reject a statically invalid width before generating executable code.
import ../../../src/codec/collections
discard scalarMinimum(CollectionUInt[-1])
