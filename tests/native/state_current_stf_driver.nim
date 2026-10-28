# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Emit original complete inputs and actual candidate successors for an independent whole-map STF oracle.
## Every child is genuinely signed; supplied raw service identities must match the complete current map.
import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/provider as chain_provider
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/state_composition as codec_state_composition
import ../../src/state/store as state_store
import ../../src/state/checkpoint as state_checkpoint
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/current_profile as state_current_profile
import ../../src/state/current_globals as state_current_globals
import ../../src/state/current_state as state_current_state
import ../../src/state/global_snapshot as state_global_snapshot
import ../support/state_accumulation_current_chain_context
import ../support/state_current_consecutive_context
import ../support/state_current_namespace_context
import ../support/state_current_typed_context
import ../support/state_inventory_context

proc hex(bytes: openArray[byte]): string =
  ## Preserve every wire octet, including zero-length present values inside the checkpoint.
  result = ""
  for octet in bytes: result.add(toHex(int(octet), 2).toLowerAscii())

proc checkpointHex(state: StateStoreSnapshot): string =
  ## Export the entire retained map through the public local checkpoint codec.
  let encoded = encodeFullCheckpoint(state, ByteLimit(100000))
  assert encoded.error == CheckpointError.None
  hex(encoded.value)

proc run(base: OwnedReport, populated: bool) =
  ## A valid six-key ring root enters the original complete parent; no source trace is repaired.
  let seeds = if populated: namespaceSeeds() else: @[]
  let context = currentChainFixture(base, ticket = true, completeState = true,
      serviceNamespaces = seeds)
  var chain = initApplicationChain(genesisView(context.parent)).value
  let original = chain.stateSnapshot.value
  echo "P ", checkpointHex(original)
  let limits = currentConsecutiveLimits()
  # Ten same-epoch children exercise history eviction, newest-eight pools and several belt carries.
  for index in 0..<10:
    let before = chain.stateSnapshot.value
    let saved = checkpointHex(before)
    let child = currentEmptyChild(chain.chainView.bestBlock.value)
    var bytes = newSeq[byte](child.blockInfo.value.consumed)
    assert child.encodeOwnedBlock(bytes).error == FrameError.None
    echo "B ", hex(bytes)
    let prepared = prepareCurrentCandidate(chain, child, [], limits)
    assert prepared.error == CurrentCandidateError.None
    let update = prepared.value
    # Current qualification verifies all sixteen globals and every supplied service namespace.
    let profile = captureCurrentProfile(update, CurrentProfileLimits(validators: ElementLimit(
        1024), bytes: ByteLimit(65536))).value
    let globals = qualifyCurrentGlobals(profile, GlobalStateLimits(chapter: StateChapterPolicy(
        items: ElementLimit(10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))).value
    let services = if populated: currentNamespaceServices(update.currentUpdateState, seeds)
      else: currentSuppliedServices(update.currentUpdateState)
    let qualified = qualifyCurrentState(globals, services, inventoryCaptureLimits)
    assert qualified.error == CurrentStateError.None
    assert checkpointHex(before) == saved
    assert chain.canInstallPrepared(update)
    chain.installPrepared(update)
    echo "O ", checkpointHex(chain.stateSnapshot.value)
  assert checkpointHex(original) == checkpointHex(context.parent.value.stateSnapshot)

proc main() {.raises.} =
  ## The maintained frozen report only seeds unused service code; all child extrinsics are empty.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let base = decodeOwnedReport(bytes, 2).value
  run(base, false)
  run(base, true)

try:
  main() # I/O and decoding failures must fail the corpus rather than emit partial successful evidence.
except:
  quit(2)
