# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copied scalar access outcomes shared by the two faithfully separated memory implementations.

type
  AccessKind* {.pure.} = enum
    ## Guest outcomes correspond to success, trap, page fault and host allocation limit.
    Ok, Trap, Segfault, MemoryLimit
  Access* = object
    ## A scalar value or fault descriptor; no memory ownership is transferred.
    kind*: AccessKind
    value*: uint64
    page*: uint32
    readOnly*: bool
