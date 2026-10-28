# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete authored chainspec startup and selected logical capture use the actual Services-owned physical parent.
import std/assertions
import std/syncio
import std/strutils
import std/monotimes
import std/times
import ./state_current_repeated_logical_context
import ./state_parent_profile_context
import ./state_parent_globals_context
import ./codec_supplied_logical_context
import ../../src/app/services as app_services
import ../../src/app/options as app_options
import ../../src/app/current_block_input as app_current_block_input
import ../../src/app/preparation_worker as app_preparation_worker
import ../../src/app/candidate as app_candidate
import ../../src/state/parent_logical as state_parent_logical
import ../../src/state/parent_globals as state_parent_globals
import ../../src/state/parent_profile as state_parent_profile
import ../../src/state/store as state_store
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/chain/provider as chain_provider
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/parameters as chain_parameters
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/header as codec_header
import ../../src/codec/block_codec as codec_block_codec
import ../../src/lib/json_writer as lib_json_writer
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
    path: string, database = "", managed = false): SelectedLogicalParent {.raises.} =
  ## Reparse actual configured state, then validate supplied declarations against that exact new physical Services owner.
  writeFile(path, logicalServicesText(fixture))
  var options = default(Options)
  var args = @["server", "--with-state", "--chain", path, "--state-writes", "1000",
    "--state-write-bytes", "1000000"]
  if database.len > 0:
    for argument in ["--state-storage", "disk", "--state-db", database]: args.add(argument)
    if managed:
      for argument in ["--state-layout", "managed", "--state-compact-bytes", "0"]: args.add(argument)
  assert parseCanonicalOptions(args, options)
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
