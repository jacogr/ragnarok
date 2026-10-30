# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Private owned source fragment; the projector removes exactly these three comment lines.
    writer*: nil pointer ## Borrowed writer, retained throughout the synchronous native invocation.
    readTag: uint64
    readPointer: nil pointer
    writeTag: uint64
    writePointer: nil pointer
    epochPointer: nil pointer
    readEpoch, writeEpoch, fastLoads, fastStores, slowLoads, slowStores: uint64
    testProbe: nil pointer
