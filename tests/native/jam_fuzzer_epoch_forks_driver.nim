# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual fuzzer ticket siblings and original-last epoch transitions preserve immutable whole-map branch contexts.
import std/[assertions, cmdline, syncio]
import ../support/[fuzz_backend_context, current_stf_epoch_context, accumulation_current_chain_context]
import ../../src/app/fuzz/[backend as fuzz_backend, rejection as fuzz_rejection]
import ../../src/chain/genesis
import ../../src/codec/[bounded, header, block_codec, report_owned, tickets]
import ../../src/state/store
import ../../src/state/fuzz/protocol as fuzz_protocol

proc observe(backend: var FuzzBackend, body: OwnedBlock): StateStoreSnapshot =
  ## Observe only a successful genuine import and exact-header whole-state query.
  var wire = newSeq[byte](body.blockInfo.value.consumed)
  assert body.encodeOwnedBlock(wire).error == FrameError.None
  let imported = backend.executeFuzz(fuzzImport(body))
  assert imported.error == FuzzBackendError.None, $imported.error
  let state = backend.executeFuzz(fuzzGetState(backend.fuzzBackendHeader.value)).value.fuzzState.value
  assert array[32, byte](imported.value.fuzzRoot.value) == array[32, byte](state.commitment.root)
  echo "B ", hex(wire)
  echo "O ", checkpointHex(state)
  state
proc run(parent: BlockSnapshot, bank: seq[BankTicket], mode: int) =
  ## Mutants always restore the exact original parent; dropping a ticket changes the contest without changing later originals.
  var config = fuzzBackendTestConfig()
  config.initialAncestry = true
  config.forkStates = ElementLimit(2)
  var backend = initFuzzBackend(config).value
  let member = FuzzAncestor(slot: HeaderSlot(uint32(parent.slot)), hash: fuzzGetState(
      parent.header).fuzzRequestedHeader.value)
  assert backend.executeFuzz(fuzzInitialize(parent.header, parent.stateSnapshot, [member])).error ==
      FuzzBackendError.None
  var selected = parent
  let original = checkpointHex(parent.stateSnapshot)
  echo "P ", original
  let slots = if mode == 0: @[2'u32, 3, 4, 5, 10, 11, 12, 13, 36, 37]
    elif mode == 1: @[2'u32, 3, 4, 5, 12, 13] else: @[2'u32, 3, 10, 11, 12, 13]
  for slot in slots:
    var submitted: seq[Ticket] = @[]
    if slot in 2'u32..5'u32:
      for index in (int(slot)-2)*3..<(int(slot)-1)*3: submitted.add(bank[index].ticket)
    elif slot == 12: submitted.add(bank[12].ticket)
    elif slot == 13: submitted.add(bank[13].ticket)
    let before = checkpointHex(selected.stateSnapshot)
    var variant = default(OwnedHeader)
    var variantMap = ""
    if submitted.len > 0:
      var fewer: seq[Ticket] = @[]
      for index in 0..<submitted.len-1: fewer.add(submitted[
          index]) # The known valid subset preserves contest order.
      let state = backend.observe(child(selected, slot, fewer, bank))
      variant = backend.fuzzBackendHeader.value
      variantMap = checkpointHex(state)
      assert checkpointHex(selected.stateSnapshot) == before
    let state = backend.observe(child(selected, slot, submitted, bank))
    if submitted.len > 0:
      assert checkpointHex(backend.executeFuzz(fuzzGetState(variant)).value.fuzzState.value) == variantMap
      assert checkpointHex(state) != variantMap # Ticket counts/contest state distinguish every sibling map.
    selected = captureBlockSnapshot(currentChainBytes(backend.fuzzBackendHeader.value), state,
        config.parameters).value
  assert checkpointHex(backend.executeFuzz(fuzzGetState(parent.header)).value.fuzzState.value) == original
proc main() {.raises.} =
  ## Fixed native Ring proofs are inputs; the independent mathematical oracle owns all successor maps.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let parent = original(decodeOwnedReport(bytes, 2).value)
  let bank = readBank(paramStr(2))
  for mode in 0..<3: run(parent, bank, mode)
try:
  main() # A refused ticket/epoch transition or unequal whole map fails the complete corpus.
except:
  quit(2)
