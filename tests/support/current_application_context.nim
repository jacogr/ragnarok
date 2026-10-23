# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent chainspec serialization starts Services from a genuine signed current fixture's complete original parent.
import std/[assertions, strutils]
import ../../src/chain/[genesis, parameters]
import ../../src/codec/header
import ../../src/state/store
import ../../src/lib/json_writer
import ./accumulation_current_chain_context
proc hexBytes(value: openArray[byte]): string =
  ## Test-owned canonical lowercase hexadecimal does not reuse the production configuration decoder.
  result = ""
  for octet in value: result.add(toHex(int(octet), 2).toLowerAscii())
proc currentApplicationText*(parent: BlockSnapshot): string =
  ## Emit every original complete-map entry and its exact sealed header/parameter tuple, never a partial-state root.
  let state = parent.stateSnapshot
  var header = newSeq[byte](parent.header.headerInfo.value.consumed)
  assert parent.header.encodeOwnedHeader(header).error == HeaderError.None
  var entries = JsonObject()
  for index in 0..<state.commitment.entries:
    let key = state.keyAt(StateEntryIndex(index)).value
    let value = state.lookup(key).value.bytes
    entries.add(hexBytes(array[31, byte](key)), json(hexBytes(value)))
  $jsonObject([("protocol_parameters", json(hexBytes(parent.chainParameters.encodeParameters))),
    ("genesis_header", json(hexBytes(header))), ("genesis_state", json(entries))])
proc currentApplicationText*(context: CurrentChainFixture): string =
  ## Preserve existing signed fixture callers through the same exact original snapshot serializer.
  currentApplicationText(context.parent.value)
