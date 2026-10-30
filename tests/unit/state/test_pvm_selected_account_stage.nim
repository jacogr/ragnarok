# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_selected_account_stage_arc_release"}

## Genuine current creation and complete prior inventory apply selected account writes atomically on a private fork.
import std/[assertions, envvars, syncio]
import ../../../src/chain/parameters
import ../../../src/pvm/[machine, step]
import ../../../src/pvm/gas/gas
import ../../../src/codec/[bounded, composite, report_owned]
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    trie as state_trie, service_values as state_service_values]
import ../../../src/state/accumulation/account/stage as accumulation_account_stage
import "../../../src/state/accumulation/block/guests" as accumulation_block_guests
import ../../../src/state/accumulation/[guest_runner as accumulation_guest_runner,
    coverage as accumulation_coverage]
import ../../../src/state/accumulation/account/selection as accumulation_account_selection
import ../../../src/state/accumulation/[creation_union as accumulation_creation_union,
    selected_writes as accumulation_selected_writes]
import ../../../src/state/store
import ../../support/[accumulation_execution_context, accumulation_runner_context,
  accumulation_current_guests_context, pvm_accumulation_program, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc createProgram(): seq[byte] =
  ## A genuine automatic new host creates metadata and its empty code request before halting.
  var payload = newSeq[byte](60)
  payload[32] = 1
  let code = guestEnvelope([registerImmediate(7, high(uint64)), registerImmediate(8, high(uint64)),
    registerImmediate(9, 0), registerImmediate(10, 196608), @[10'u8, 20], @[50'u8, 0]],
        writable = payload)
  result = @[0'u8]
  for octet in code: result.add(octet) # Complete service preimage retains its canonical metadata prefix.
proc main() {.raises.} =
  ## Every fixture is signed/admitted through production; source maps never publish a prepared account stage.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve exact binary report framing.
  let base = decodeOwnedReport(wire, 2).value
  var options = executionFixtureConfig()
  options.firstProgram = createProgram()
  var opaque = default(array[31, byte])
  opaque[0] = 255
  opaque[30] = 9
  options.signed.extra = @[
    serviceMetadataEntry(ServiceIndex(1), ServiceMetadata(balance: AccountBalance(7)), ByteLimit(
        ServiceMetadataBytes)).value,
    serviceMetadataEntry(ServiceIndex(256), ServiceMetadata(balance: AccountBalance(8)), ByteLimit(
        ServiceMetadataBytes)).value,
    StateEntry(key: StateKey(opaque), value: @[3'u8])]
  let fixture = executionFixture(base, options)
  let prior = fixture.state.snapshot.value
  var guestLimits = currentGuestLimits()
  guestLimits.copyBytes = MemoryByteLimit(128)
  guestLimits.steps = ExecutionStepLimit(200)
  guestLimits.calls = HostCallLimit(32)
  guestLimits.modifiedAccounts = ElementLimit(8)
  guestLimits.accountWriteFacts = ElementLimit(8)
  let guests = runBlockAccumulationGuests(fixture.round, currentGuestParameters(),
      guestLimits).value
  let prepared = prepareAccumulationAccountStage(guests, currentAccountStageLimits())
  assert prepared.error == AccumulationAccountStageError.None, $prepared.error
  let stage = prepared.value
  let info = stage.accountStageInfo.value
  assert info.priorAccounts == 4 and info.newAccounts == 1 and info.writes == 3
  let selected = stage.accountStageSelection.value
  for index, service in [1'u32, 42'u32, 99'u32, 256'u32]:
    let row = selected.selectedAccountAt(AccumulationAccountSelectionIndex(uint64(index))).value
    assert uint32(row.service) == service # Canonical numeric order differs from little-endian trie order.
  let child = stage.accountStageCreation.value.createdAccountAt(AccumulationCreationIndex(
      0)).value.service
  let after = stage.accountStageSnapshot.value
  assert prior.lookup(chapterServiceKey(StateChapter(255), child)).error ==
      StateStoreError.MissingKey
  assert after.lookup(chapterServiceKey(StateChapter(255), child)).error == StateStoreError.None
  assert after.lookup(StateKey(opaque)).value.bytes == @[3'u8], "nonmetadata255 key remains opaque"
  var oracle = forkStateStore(prior).value
  let facts = stage.accountStageWrites.value
  var writes: seq[StateWrite] = @[]
  for index in 0..<info.writes:
    writes.add(facts.selectedWriteAt(AccumulationSelectedWriteIndex(uint64(index))).value)
  let manual = oracle.apply(writes).value
  assert array[32, byte](manual.commitment.root) == array[32, byte](after.commitment.root)
  assert sameStateSnapshot(fixture.state.snapshot.value, prior)
  for mode in 0..<4:
    var limits = currentAccountStageLimits()
    case mode
    of 0: limits.entries = ElementLimit(0) # Inventory work must fail before scanning.
    of 1: limits.providers = ElementLimit(1) # Every no-op/ready provider still consumes traversal capacity.
    of 2: limits.selection.accounts = ElementLimit(3) # Prior membership cannot be silently omitted.
    else: limits.writes.writes = ElementLimit(2) # The complete physical write set cannot be truncated.
    assert prepareAccumulationAccountStage(guests, limits).error !=
        AccumulationAccountStageError.None
  var disabled = guestLimits
  disabled.accountWriteFacts = ElementLimit(0)
  let noFacts = runBlockAccumulationGuests(fixture.round, currentGuestParameters(), disabled).value
  let refused = prepareAccumulationAccountStage(noFacts, currentAccountStageLimits())
  assert refused.error == AccumulationAccountStageError.WriteFailure
  assert refused.writeFailure == SelectedAccountWriteError.IncompleteFacts
  disabled = guestLimits
  disabled.createdAccounts = ElementLimit(0)
  let noCreation = runBlockAccumulationGuests(fixture.round, currentGuestParameters(),
      disabled).value
  let creationFailure = prepareAccumulationAccountStage(noCreation, currentAccountStageLimits())
  assert creationFailure.error == AccumulationAccountStageError.CreationFailure
  assert creationFailure.creationFailure == AccumulationCreationError.IncompleteFacts
  failHash(1)
  let backend = prepareAccumulationAccountStage(guests, currentAccountStageLimits())
  assert backend.error == AccumulationAccountStageError.StoreFailure
  assert backend.storeFailure == StateStoreError.BackendFailure
  failHash(0)
  assert sameStateSnapshot(fixture.state.snapshot.value, prior), "late private Merkle refusal never publishes source state"
  let unchanged = executionFixture(base)
  let noWrites = runBlockAccumulationGuests(unchanged.round, runnerParameters(), currentGuestLimits()).value
  let identity = prepareAccumulationAccountStage(noWrites, currentAccountStageLimits()).value
  assert identity.accountStageInfo.value.writes == 0
  assert sameStateSnapshot(identity.accountStageSnapshot.value, unchanged.state.snapshot.value)
  var malformedOptions = executionFixtureConfig()
  malformedOptions.signed.extra = @[StateEntry(key: chapterServiceKey(StateChapter(255),
      ServiceIndex(256)), value: @[1'u8])]
  let malformed = executionFixture(base, malformedOptions)
  let malformedGuests = runBlockAccumulationGuests(malformed.round, runnerParameters(),
      currentGuestLimits()).value
  let badAccount = prepareAccumulationAccountStage(malformedGuests, currentAccountStageLimits())
  assert badAccount.error == AccumulationAccountStageError.SelectionFailure
  assert badAccount.selectionFailure == AccumulationAccountSelectionError.MalformedState
  var emptyOptions = executionFixtureConfig()
  emptyOptions.empty = true
  let empty = executionFixture(base, emptyOptions)
  let emptyGuests = runBlockAccumulationGuests(empty.round, runnerParameters(), currentGuestLimits()).value
  let emptyStage = prepareAccumulationAccountStage(emptyGuests, currentAccountStageLimits()).value
  assert emptyStage.accountStageInfo.value.priorAccounts == 2
  assert sameStateSnapshot(emptyStage.accountStageSnapshot.value, empty.state.snapshot.value), "empty execution still covers the complete prior account domain"
  let invalidSource = prepareAccumulationAccountStage(default(BlockAccumulationGuests),
      currentAccountStageLimits())
  assert invalidSource.error == AccumulationAccountStageError.InvalidSource
  assert default(PreparedAccumulationAccountStage).accountStageSnapshot.error ==
      AccumulationAccountStageError.Uninitialized
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareAccumulationAccountStage(guests, currentAccountStageLimits()).value
    assert local.accountStageInfo.value.newAccounts ==
        1 # New paths, complete selected owners and inherited forks all release.
  let occupied = getOccupiedMem()
  assert before == occupied, "selected account phase owners release"
  recordArcRelease("pvm_selected_account_stage", 1000, before, occupied)
  echo "PVM selected account stage passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Unexpected admission, setup or native failure must fail the suite.
except:
  quit(2)
