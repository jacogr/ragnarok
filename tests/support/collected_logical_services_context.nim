# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete authored chainspec startup and selected logical capture use the actual Services-owned physical parent.
import std/[assertions, syncio, strutils, monotimes, times]
import ./[current_repeated_logical_context, parent_profile_context, parent_globals_context,
    supplied_logical_context]
import ../../src/app/[services, options, current_block_input, preparation_worker, candidate]
import ../../src/state/[parent_logical, parent_globals, parent_profile, store, accumulation_current_update]
import ../../src/chain/[provider, genesis, parameters]
import ../../src/codec/[bounded, header, block_codec]
import ../../src/lib/json_writer
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield scalar native phase polling under an explicit monotonic deadline.
proc hexBytes(value: openArray[byte]): string =
  ## Test-owned chainspec text uses independent lowercase hexadecimal encoding.
  result = ""
  for octet in value: result.add(toHex(int(octet), 2).toLowerAscii())
proc logicalServicesText*(fixture: CurrentRepeatedLogicalFixture): string =
  ## Serialize the original complete authored signed parent; no successor map is repaired or installed.
  let parent = fixture.first.update.currentUpdatePriorView.bestBlock.value
  let state = parent.stateSnapshot
  var headerBytes = newSeq[byte](parent.header.headerInfo.value.consumed)
  assert parent.header.encodeOwnedHeader(headerBytes).error == HeaderError.None
  var entries = JsonObject()
  for i in 0..<state.commitment.entries:
    let key = state.keyAt(StateEntryIndex(i)).value
    entries.add(hexBytes(array[31, byte](key)), json(hexBytes(state.lookup(key).value.bytes)))
  $jsonObject([("protocol_parameters", json(hexBytes(parent.chainParameters.encodeParameters))),
    ("genesis_header", json(hexBytes(headerBytes))), ("genesis_state", json(entries))])
proc startLogicalServices*(owner: var Services, fixture: CurrentRepeatedLogicalFixture,
    path: string): SelectedLogicalParent {.raises.} =
  ## Reparse actual configured state, then validate supplied declarations against that exact new physical Services owner.
  writeFile(path, logicalServicesText(fixture))
  var options = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", path, "--state-writes", "1000",
    "--state-write-bytes", "1000000"], options)
  assert owner.start(options, "collected logical state")
  let profile = captureParentProfile(owner.chainView, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  captureLogicalParent(globals, fixture.first.services, suppliedLogicalTestLimits).value
proc waitManagedPreparation*(owner: var Services) {.raises.} =
  ## Tick only supported dispatcher/scalar work while canonical aliases remain exclusively borrowed.
  let start = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20
    owner.tick(0)
    discard pauseMicros(1000)
proc beginManagedCurrent*(owner: var Services, input: var CurrentBlockInput,
    wire: openArray[byte], ancestors: openArray[OwnedHeader],
    policies: CurrentCandidateLimits): PreparationTicket {.raises.} =
  ## Receive on the host and return only a scalar ticket after managed submission; all temporary canonical aliases retire first.
  let admitted = owner.beginBlockInput(input, ByteLimit(uint64(wire.len)), ancestors,
    CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(wire.len)), ancestorBytes: ByteLimit(65536),
      ancestors: ElementLimit(4)), policies)
  assert admitted.error == CurrentBlockInputError.None
  assert input.append(admitted.value, wire, true) == CurrentBlockInputError.None
  owner.beginPreparation(input, admitted.value).value
