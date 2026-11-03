# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent fixture ALPN formatting for real command responders on their configured genesis.
import std/[assertions, syncio, strutils]
import ../../src/chain/genesis
import ../../src/rpc/protocol

proc fixtureChainAlpn*(path: string): string {.raises.} =
  ## Fixture paths are authored before listener startup; only complete configured genesis is accepted.
  let text = readFile(path)
  let parameters = configuredParameters(text)
  assert parameters.ok, "configured fixture parameters: " & path
  let genesis = configuredGenesis(text, parameters.value)
  assert genesis.error == GenesisError.None, "configured fixture genesis: " & path & ": " & $genesis.error
  let hash = array[32, byte](genesis.value.blockHash)
  result = "jamnp-s/1/"
  for index in 0..<4: result.add(toHex(int(hash[index]), 2).toLowerAscii()) # Use independent standard hex formatting.
