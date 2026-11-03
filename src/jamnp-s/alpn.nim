# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JAMNP-S version-one protocol identifiers. Both node and builder offers share one chain
## prefix; accepting the builder suffix grants no validator or work-package authority.

import std/strutils

proc validAlpn*(name: string): bool =
  ## Accept only the pinned ASCII version/genesis spelling, excluding truncation and extra suffixes.
  if name.len != 18 and name.len != 26: return false
  if not name.startsWith("jamnp-s/1/"): return false
  for index in 10..<18:
    if name[index] notin {'0'..'9', 'a'..'f'}: return false # Eight lower-case nibbles bind the configured chain domain.
  name.len == 18 or name.endsWith("/builder")

proc serverAlpns*(name: string): seq[string] =
  ## Return the two allowed acceptor identifiers; malformed input produces no usable protocol list.
  if not validAlpn(name): return @[]
  let base = name.substr(0, 17)
  @[base, base & "/builder"]
