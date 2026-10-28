# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently authored minimal chain fixture shared by MCP protocol and service tests.
import std/strutils

proc mcpChainText*(): string =
  ## Six zero-key validators and slot seven form an explicit configured header/state pair.
  let wire = repeat("00", 32) & repeat("11", 32) & repeat("00", 32) & "07000000" & repeat("00", 197)
  let roster = "08" & repeat("00", 30)
  let clock = "0b" & repeat("00", 30)
  "{\"protocol_parameters\":\"ffffffffffffffff02000000000000000300000000000000040005000000580200000700000000000000080000000000000009000000000000000a000000000000000b000c000d000e000f000000100011001200130014001500160000001700000018000000190000001a0000001b0000001c000000f4010000\",\"genesis_header\":\"" & wire &
    "\",\"genesis_state\":{\"" & roster & "\":\"06" & repeat("00", 2016) & "\",\"" & clock & "\":\"07000000\"}}"
