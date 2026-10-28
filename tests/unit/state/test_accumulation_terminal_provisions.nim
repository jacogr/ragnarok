# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_terminal_provisions_arc_release"}

## Actual terminal selection binds bounded provision union and timestamps to invocation provenance.
## Covers atomic fulfillment, normalization preflight, copied ownership, guarded refusals and ARC release.

import std/[assertions, syncio]
import ../../../src/state/[accumulation_terminal_provisions, accumulation_dispatch,
  accumulation_outcome, accumulation_provisions, accumulation_context, accumulation_effects, store]
import ../../../src/codec/[bounded, composite, header, state_accounts, state_service_values, state_trie]
import ../../../src/pvm/step
import ../../../src/crypto/primitives
import ../../support/[accumulation_terminal_provisions, accumulation_provision_integration,
  pvm_accumulation_provision, arc_evidence]

# Disable hashing only after all genuine execution and posterior fixtures exist.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Count backend invocations to prove terminal preflight and cached replay perform no hashes.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Inspect only the complete map's existing commitment, never a partial reconstruction.
proc root(state: StateStore): array[32, byte] = array[32, byte](
    state.snapshot.value.commitment.root)

# Independently construct exact singleton timestamp bytes and full expected-map commitments.
proc expectedEntries(second: bool, first = true): seq[StateEntry] =
  result = terminalPosteriorEntries()
  for service in [42'u32, 99'u32]:
    if (service == 42 and first) or (service == 99 and second):
      let bytes = (if service == 42: @[73'u8] else: @[81'u8])
      let key = provisionRequest(service, bytes).key
      for index in 0..<result.len:
        if array[31, byte](result[index].key) == array[31, byte](key):
          result[index].value = @[1'u8, 128, 0, 0, 0] # Literal count + E4 invocation slot 128.
      # A maintained namespace primitive derives the preimage key; expected raw bytes remain literal.
      result.add(servicePreimageEntry(ServiceIndex(service),
        ServicePreimageHash(array[32, byte](blake2b256(bytes).value)), bytes,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value)

let halted = terminalProvisionExecution()
let panicked = terminalProvisionExecution(TerminalProvisionEnding.Panic)
let faulted = terminalProvisionExecution(TerminalProvisionEnding.Fault)
let exhausted = terminalProvisionExecution(TerminalProvisionEnding.OutOfGas)
let uncheckpointed = terminalProvisionExecution(TerminalProvisionEnding.Panic, checkpoint = false)
let hashReturn = terminalProvisionExecution(TerminalProvisionEnding.HashReturn)
let invalidExecution = default(AccumulationDispatchResult)
assert halted.error == AccumulationDispatchError.None and halted.value.exit == StepExit.Halt
assert panicked.value.exit == StepExit.Panic and faulted.value.exit == StepExit.Fault
assert exhausted.value.exit == StepExit.OutOfGas
let slot = HeaderSlot(128)
let policy = integrationPolicy(contexts = 3, items = 5, perBlob = 1, total = 5, encoded = 13)
let executions = @[hashReturn, panicked, hashReturn]
let plan = prepareTerminalAccumulationProvisions(executions, slot, policy).value
let info = plan.terminalProvisionInfo.value
assert uint32(info.slot) == 128
assert info.provisions.contexts == 3 and info.provisions.inputItems == 5 and
    info.provisions.items == 2
assert uint64(info.provisions.inputBytes) == 5 and uint64(info.provisions.bytes) == 2
for index in 0..<3:
  let selected = plan.terminalProvisionOutcomeAt(AccumulationProvisionSourceIndex(uint64(index))).value
  let facts = selected.outcomeInfo.value
  assert uint32(facts.service) == 42
  assert facts.dimension == (if index == 1: AccumulationDimension.Exceptional else: AccumulationDimension.Regular)
  assert facts.provisions == (if index == 1: 1 else: 2)
  assert uint64(facts.gasUsed) > 0
assert plan.terminalProvisionOutcomeAt(AccumulationProvisionSourceIndex(3)).error ==
  AccumulationTerminalProvisionError.InvalidIndex
assert plan.terminalProvisionOutcomeAt(AccumulationProvisionSourceIndex(high(uint64))).error ==
  AccumulationTerminalProvisionError.InvalidIndex
let defaultPlan = default(PreparedTerminalAccumulationProvisions)
assert defaultPlan.terminalProvisionInfo.error == AccumulationTerminalProvisionError.Uninitialized
assert defaultPlan.terminalProvisionOutcomeAt(AccumulationProvisionSourceIndex(0)).error ==
  AccumulationTerminalProvisionError.Uninitialized
let defaultResult = default(AccumulationTerminalProvisionResult[
    PreparedTerminalAccumulationProvisions])
assert defaultResult.error == AccumulationTerminalProvisionError.Uninitialized
for limited in [integrationPolicy(contexts = 2), integrationPolicy(items = 4),
    integrationPolicy(perBlob = 0), integrationPolicy(total = 4), integrationPolicy(encoded = 12)]:
  let refused = prepareTerminalAccumulationProvisions(executions, slot, limited)
  if uint64(limited.contexts) == 2:
    assert refused.error == AccumulationTerminalProvisionError.LimitExceeded # Refuse descriptors before normalization.
  else:
    assert refused.error == AccumulationTerminalProvisionError.ProvisionFailure
    assert refused.provisionError == AccumulationProvisionError.LimitExceeded
let empty = prepareTerminalAccumulationProvisions([], HeaderSlot(high(uint32)),
  integrationPolicy(contexts = 0, items = 0, perBlob = 0, total = 0, encoded = 1)).value
assert empty.terminalProvisionInfo.value.provisions.items == 0
assert uint32(empty.terminalProvisionInfo.value.slot) == high(uint32)
let emptyRefusal = prepareTerminalAccumulationProvisions([], slot, integrationPolicy(encoded = 0))
assert emptyRefusal.provisionError == AccumulationProvisionError.LimitExceeded
# Every terminal refusal wins before hashing an earlier valid context's provision bytes.
failHash(1)
for badSlot in [0'u32, 127, 129, high(uint32)]:
  assert prepareTerminalAccumulationProvisions([halted], HeaderSlot(badSlot), policy).error ==
    AccumulationTerminalProvisionError.InvalidSlot
let invalid = prepareTerminalAccumulationProvisions([halted, default(AccumulationDispatchResult)],
    slot, policy)
assert invalid.error == AccumulationTerminalProvisionError.NormalizationFailure
assert invalid.normalizationError == AccumulationOutcomeError.InvalidExecution
let lateInvalid = prepareTerminalAccumulationProvisions([hashReturn, invalidExecution], slot, policy)
assert lateInvalid.error == AccumulationTerminalProvisionError.NormalizationFailure
assert lateInvalid.normalizationError == AccumulationOutcomeError.InvalidExecution
assert hashCalls() == 0
let refusal = prepareTerminalAccumulationProvisions([halted], slot, policy)
assert refusal.error == AccumulationTerminalProvisionError.ProvisionFailure
assert refusal.provisionError == AccumulationProvisionError.BackendFailure
failHash(0)
let expectedBoth = newStateStore(expectedEntries(true), integrationStoreLimits()).value
let expectedCheckpoint = newStateStore(expectedEntries(false), integrationStoreLimits()).value
let posterior = newStateStore(terminalPosteriorEntries(), integrationStoreLimits()).value
for index, execution in [halted, panicked, faulted, exhausted, uncheckpointed, hashReturn]:
  let selectedPlan = prepareTerminalAccumulationProvisions([execution], slot, policy).value
  let selected = selectedPlan.terminalProvisionOutcomeAt(AccumulationProvisionSourceIndex(0)).value
  let facts = selected.outcomeInfo.value
  var state = posterior
  let before = root(state)
  assert integrateTerminalAccumulationProvisions(state, selectedPlan).error ==
      AccumulationTerminalProvisionError.None
  let expected = (if index == 0 or index == 5: root(expectedBoth)
    elif index == 4: before else: root(expectedCheckpoint))
  assert root(state) == expected # Only the independently expected normalized dimension reaches fnprovide.
  let expectedCount = (if index == 0 or index == 5: 2 elif index == 4: 0 else: 1)
  assert facts.provisions == expectedCount
# Reachable X/Y combinations distinguish the adopted regular projection from checkpoint selection.
for first in [false, true]:
  for second in [false, true]:
    for checkpoint in [false, true]:
      let execution = terminalProvisionExecution(TerminalProvisionEnding.HashReturn,
        checkpoint = checkpoint, second = second, first = first)
      let count = (if first: 1 else: 0)+(if second: 1 else: 0)
      failHash(1)
      let normalized = normalizeAccumulationOutcome(execution).value
      let context = normalized.outcomeContext.value
      let facts = normalized.outcomeInfo.value
      assert facts.dimension == AccumulationDimension.Regular and facts.provisions == count and
          facts.hasYield,
        "hash return retains exactly X's provisions for empty, equal and divergent checkpoint histories"
      let commitment = array[32, byte](context.effectYield.value)
      assert commitment[0] == 73
      for index in 1..<32:
        assert commitment[index] == 0, "readable RO return is an exact independently authored 32-byte commitment"
      var services: seq[uint32] = @[]
      var octets: seq[byte] = @[]
      if first:
        services.add(42)
        octets.add(73) # First provided byte and its real target are independent expected observations.
      if second:
        services.add(99)
        octets.add(81) # The newer regular contribution must not disappear when Y retained only the first.
      for index in 0..<count:
        let provision = context.effectProvisionAt(AccumulationProvisionIndex(uint64(index))).value
        assert uint32(provision.provisionInfo.value.service) == services[index]
        assert provision.copyProvisionBytes.value == @[octets[index]]
      let regular = execution.effects.effectContext(
          AccumulationDimension.Regular).value.effectInfo.value
      let exceptional = execution.effects.effectContext(
          AccumulationDimension.Exceptional).value.effectInfo.value
      assert regular.provisions == count and not regular.hasYield,
        "yield override leaves the original regular effects immutable"
      assert exceptional.provisions == (if first and checkpoint: 1 else: 0) and
          not exceptional.hasYield,
        "normalization never mutates or substitutes checkpoint provisions"
      assert hashCalls() == 0, "provision-preserving hash-return normalization performs no hashing"
      failHash(0)
      let selected = prepareTerminalAccumulationProvisions([execution], slot, policy).value
      let expected = newStateStore(expectedEntries(second, first), integrationStoreLimits()).value
      var state = posterior
      discard integrateTerminalAccumulationProvisions(state, selected).value
      assert root(state) == root(expected),
        "complete independent map contains exactly the selected regular provision timestamps and preimages"
# Caller sequence replacement and copied metadata edits cannot retarget outcomes or timestamps.
var retained: PreparedTerminalAccumulationProvisions
block:
  var inputs = @[terminalProvisionExecution(), terminalProvisionExecution(
      TerminalProvisionEnding.Panic)]
  retained = prepareTerminalAccumulationProvisions(inputs, slot, policy).value
  inputs[0] = default(AccumulationDispatchResult)
  inputs.setLen(0)
var changed = retained.terminalProvisionInfo.value
changed.slot = HeaderSlot(7)
changed.provisions.items = 0
assert retained.terminalProvisionInfo.value.provisions.items == 2
assert uint32(retained.terminalProvisionInfo.value.slot) == 128
var applied = posterior
assert integrateTerminalAccumulationProvisions(applied, retained).error ==
    AccumulationTerminalProvisionError.None
assert root(applied) == root(expectedBoth)
failHash(1)
assert integrateTerminalAccumulationProvisions(applied, retained).error ==
    AccumulationTerminalProvisionError.None
assert integrateTerminalAccumulationProvisions(applied, empty).error ==
    AccumulationTerminalProvisionError.None
assert hashCalls() == 0 # Replays and empty batches keep cached identities and perform no root work.
failHash(0)
# A cancelled posterior request is skipped even though the actual selected outcome retained it.
var cancelled = posterior
let cancelledKey = provisionRequest(42, @[73'u8]).key
discard cancelled.apply([StateWrite(key: cancelledKey, kind: StateWriteKind.Delete)]).value
assert integrateTerminalAccumulationProvisions(cancelled, plan).error ==
    AccumulationTerminalProvisionError.None
assert cancelled.snapshot.value.lookup(cancelledKey).error == StateStoreError.MissingKey
let fulfilled = provisionRequest(99, @[81'u8]).key
assert cancelled.snapshot.value.lookup(fulfilled).value.bytes == @[1'u8, 128, 0, 0, 0]
var noWrites = newStateStore(terminalPosteriorEntries(), integrationStoreLimits(writes = 3)).value
let beforeWrites = root(noWrites)
let limited = integrateTerminalAccumulationProvisions(noWrites, plan)
assert limited.provisionError == AccumulationProvisionError.LimitExceeded
assert root(noWrites) == beforeWrites
var malformed = posterior
let request = provisionRequest(99, @[81'u8])
discard malformed.apply([StateWrite(key: request.key, kind: StateWriteKind.Put, value: @[4'u8])]).value
let beforeMalformed = root(malformed)
let badHistory = integrateTerminalAccumulationProvisions(malformed, plan)
assert badHistory.provisionError == AccumulationProvisionError.MalformedState
assert root(malformed) == beforeMalformed
var invalidState: StateStore
assert integrateTerminalAccumulationProvisions(invalidState, plan).provisionError ==
    AccumulationProvisionError.InvalidState
assert integrateTerminalAccumulationProvisions(applied, defaultPlan).error ==
    AccumulationTerminalProvisionError.Uninitialized
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Candidate owners release after backend refusal, normalizer refusal, successful fulfillment and no-hash replay.
  failHash(1)
  let refused = prepareTerminalAccumulationProvisions([halted], slot, policy)
  assert refused.provisionError == AccumulationProvisionError.BackendFailure
  failHash(0)
  assert prepareTerminalAccumulationProvisions([hashReturn, invalidExecution],
      slot, policy).normalizationError ==
    AccumulationOutcomeError.InvalidExecution
  let prepared = prepareTerminalAccumulationProvisions(executions, slot, policy).value
  var state = posterior
  failHash(1)
  let failed = integrateTerminalAccumulationProvisions(state, prepared)
  assert failed.provisionError == AccumulationProvisionError.BackendFailure
  assert root(state) == root(posterior)
  failHash(0)
  assert integrateTerminalAccumulationProvisions(state, prepared).error ==
      AccumulationTerminalProvisionError.None
  assert root(state) == root(expectedBoth)
  failHash(1)
  assert integrateTerminalAccumulationProvisions(state, prepared).error ==
      AccumulationTerminalProvisionError.None
  assert hashCalls() == 0
  failHash(0)
let after = getOccupiedMem()
assert before == after
recordArcRelease("accumulation_terminal_provisions", 1000, before, after)
echo "Terminal accumulation provisions passed"
echo "ARC_RELEASE cycles=1000 unchanged"
