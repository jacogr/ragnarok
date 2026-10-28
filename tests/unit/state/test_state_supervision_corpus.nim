# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent dictionary expectations qualify sparse full-domain supervisor resolution and batch lookup across all declaration orders.
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_inventory_context
import ../../support/testing_fixed_arithmetic_corpus
import ../../../src/state/inventory as state_inventory
import ../../../src/state/service_directory as state_service_directory
import ../../../src/state/service_supervision as state_service_supervision
import ../../../src/state/supervision_table as state_supervision_table
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_composition as codec_state_composition
include ../../native/nimony_composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Disable hashes only after each independent complete directory is built.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Supervisor readers and batch observations must remain hash-free.
proc order(rank: int): array[3, int] =
  ## Enumerate all six original declaration orders without aliased in-place swaps.
  result = default(array[3, int])
  var used = default(array[3, bool])
  var remainder = rank
  for position in 0..<3:
    let factor = if position == 0: 2 else: 1
    var choice = remainder div factor
    remainder = remainder mod factor
    for candidate in 0..<3:
      if not used[candidate]:
        if choice == 0:
          result[position] = candidate
          used[candidate] = true
          break # Choose each remaining identity once.
        choice -= 1
proc check(fixture: seq[seq[byte]], row: seq[byte], rank: int) =
  ## Source encoding/sorting is independent of the reference dictionary's authored decision columns.
  var services: seq[StateService] = @[]
  for target in order(rank):
    let offset = target*48
    for field in 0..<6:
      assert corpusWord(row, offset+field*8) <= uint64(high(
          uint32)) # Validate nominal narrowing even for pinned fixture inputs.
    services.add(StateService(service: ServiceIndex(uint32(corpusWord(row, offset))),
      metadata: ServiceMetadata(created: AccountSlot(uint32(corpusWord(row, offset+8))),
        supervisor: ServiceIndex(uint32(corpusWord(row, offset+16))),
            supervisorCreated: AccountSlot(uint32(corpusWord(row, offset+24))))))
  fail(0)
  let source = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  let directory = buildStateServiceDirectory(source, ServiceDirectoryLimits(services: ElementLimit(
      3), comparisons: ElementLimit(3), bytes: ByteLimit(4096))).value
  fail(1)
  let table = buildSupervisionTable(directory, SupervisionTableLimits(services: ElementLimit(3),
      bytes: ByteLimit(4096))).value
  for target in 0..<3:
    let offset = target*48
    let service = ServiceIndex(uint32(corpusWord(row, offset)))
    let expected = corpusWord(row, offset+32)
    let reason = corpusWord(row, offset+40)
    assert reason <= 2
    let selected = resolveServiceSupervision(directory, service).value.supervisionInfo.value
    assert uint64(selected.effective) == expected and uint64(ord(selected.decision)) == reason
    let batch = table.supervisionFor(service).value
    assert uint64(batch.effective) == expected and uint64(ord(batch.decision)) ==
        reason # Original-order table lookup must agree with the independent dictionary under every order.
  assert resolveServiceSupervision(directory, ServiceIndex(98)).error ==
      ServiceSupervisionError.NoService
  assert calls() == 0
  fail(0)
proc main() {.raises.} =
  ## Each512-row independent configuration is checked against all six complete declaration orders.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  let records = arithmeticCorpus(getEnv("RAGNAROK_SUPERVISION_CORPUS"), 512, 144)
  for row in records:
    for rank in 0..<6:
      check(fixture, row, rank) # Retire each directory/table graph before the next order/configuration.
  echo "state-supervision-corpus: ok (3072 cases)"
try:
  main()
except:
  quit(2) # Fixture errors cannot qualify independent authority-selection evidence.
