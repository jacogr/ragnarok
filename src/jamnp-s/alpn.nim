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

proc selectChainAlpn*(configured, requested: string, chainSelected: bool): string =
  ## Empty output refuses unavailable genesis or a conflicting explicit version/chain domain.
  if configured.len > 0:
    if not validAlpn(configured) or configured.len != 18: return ""
    if requested.len == 0: return configured
    if not validAlpn(requested) or requested.substr(0, 17) != configured: return ""
    return requested
  if chainSelected: return "" # An explicit incomplete chain never falls back to the isolated development domain.
  if requested.len == 0: return "jamnp-s/1/00000000"
  if validAlpn(requested): return requested
  ""
