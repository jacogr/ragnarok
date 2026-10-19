# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native state-only yield/checkpoint assertions against independent fixed-value history expectations.
## Hastur entry point verifies credited provenance, immutable dimensions, refusal/absence and ARC release.

import std/[assertions, syncio]
import ../../../src/state/[accumulation_effects, accumulation_context, accumulation_invocation,
  accumulation_service, accumulation_inputs, store]
import ../../../src/codec/[bounded, composite, state_outputs, state_accounts, state_privileges,
  state_authorization, state_safrole, state_trie, state_layout, c2_records]
import ../../support/[accumulation_effect_context, arc_evidence]

## Refuse hashing only after genuine prepared source construction; effect transitions must never invoke it.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## Pattern every hash byte to expose truncation, order reversal and accidental default-value replacement.
proc commitment(seed: int): OutputCommitment =
  var bytes = default(array[32, byte])
  # Small authored indices keep addition in native range before reduction to one octet.
  for i in 0..<32: bytes[i] = byte((seed+i) mod 256)
  OutputCommitment(bytes)

## Check current facts and exact source children in addition to the selected optional commitment.
proc check(context: AccumulationEffectContext, present: bool, expected: OutputCommitment) =
  let info = context.effectInfo.value
  assert uint32(info.service) == 42 and info.transfers == 0 and info.provisions == 0
  assert info.hasYield == present
  if present:
    assert array[32, byte](context.effectYield.value) == array[32, byte](expected) # Zero is present, not absence.
  else:
    assert context.effectYield.error == AccumulationEffectError.YieldAbsent # Absence exposes no hash payload.
  let initial = context.effectInitialContext.value
  assert uint64(initial.contextSelf.value.balance) == 17
  let state = initial.contextAccounts.value
  assert state.lookup(chapterKey(StateChapter(250))).value.bytes == @[9'u8, 4, 2]
  let metadata = state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(42))).value
  assert uint64(decodeServiceMetadata(metadata.bytes, ByteLimit(89)).value.metadata.balance) == 17
  assert uint32(initial.contextSelf.value.lastAccumulation) == 3
  assert uint32(initial.contextPrivileges.value.privilegeInfo.value.manager) == 11
  assert initial.contextQueues.value.authorizerCount(AuthorizationCoreIndex(1)).value == 80
  assert uint64(initial.contextStaging.value.validatorCount.value) == 6
  let invocation = initial.contextInvocation.value
  assert uint32(info.nextService) == uint32(invocation.bootstrapInfo.value.nextService)
  assert uint64(invocation.bootstrapInfo.value.inputs) == 1
  let service = invocation.bootstrapService.value
  assert uint64(service.serviceInputAt(InvocationInputIndex(0)).value.transfer.amount) == 7
  let original = service.servicePriorState.value.lookup(chapterServiceKey(StateChapter(255),
      ServiceIndex(42))).value
  assert uint64(decodeServiceMetadata(original.bytes, ByteLimit(89)).value.metadata.balance) == 10

## Independent versions distinguish yield replacement, explicit checkpoints and present zero commitments.
proc versions(): AccumulationEffectContext =
  let source = preparedEffectContexts()
  let empty = prepareAccumulationEffects(source).value
  let initialRoot = array[32, byte](source.initialContext(
      AccumulationDimension.Regular).value.contextAccounts.value.commitment.root)
  let zero = default(OutputCommitment)
  failHash(1)
  let unchanged = checkpointAccumulationEffects(empty).value
  let yielded = recordAccumulationYield(unchanged, zero).value
  let saved = checkpointAccumulationEffects(yielded).value
  let replaced = recordAccumulationYield(saved, commitment(7)).value
  let savedAgain = checkpointAccumulationEffects(replaced).value
  let final = recordAccumulationYield(savedAgain, commitment(19)).value
  # Every old pair keeps its own regular/exceptional versions after all later operations.
  for dimension in [AccumulationDimension.Regular, AccumulationDimension.Exceptional]:
    check(empty.effectContext(dimension).value, false, zero)
    check(unchanged.effectContext(dimension).value, false, zero)
    check(saved.effectContext(dimension).value, true, zero)
    check(savedAgain.effectContext(dimension).value, true, commitment(7))
  check(yielded.effectContext(AccumulationDimension.Regular).value, true, zero)
  check(yielded.effectContext(AccumulationDimension.Exceptional).value, false, zero)
  check(replaced.effectContext(AccumulationDimension.Regular).value, true, commitment(7))
  check(replaced.effectContext(AccumulationDimension.Exceptional).value, true, zero)
  check(final.effectContext(AccumulationDimension.Regular).value, true, commitment(19))
  check(final.effectContext(AccumulationDimension.Exceptional).value, true, commitment(7))
  let retained = final.effectsSource.value.initialContext(AccumulationDimension.Regular).value
  assert array[32, byte](retained.contextAccounts.value.commitment.root) == initialRoot
  var copied = array[32, byte](final.effectContext(
      AccumulationDimension.Regular).value.effectYield.value)
  copied[0] = copied[0] xor 255
  check(final.effectContext(AccumulationDimension.Regular).value, true, commitment(19))
  failHash(0)
  result = final.effectContext(AccumulationDimension.Exceptional).value

## A scalar model tracks both dimensions through repeated yield/overwrite/checkpoint histories.
proc history() =
  var current = prepareAccumulationEffects(preparedEffectContexts()).value
  var regularPresent = false
  var exceptionalPresent = false
  var regular = default(OutputCommitment)
  var exceptional = default(OutputCommitment)
  # Each step checks both dimensions; checkpoint positions vary independently of yield values.
  for step in 0..<256:
    let before = current
    let previousPresent = regularPresent
    let previous = regular
    if step mod 5 == 0 or step mod 7 == 0:
      current = checkpointAccumulationEffects(current).value # Only checkpoint changes the exceptional model.
      exceptionalPresent = regularPresent
      exceptional = regular
    else:
      regular = commitment(step)
      regularPresent = true
      current = recordAccumulationYield(current, regular).value # Yield replaces only the regular model.
    check(before.effectContext(AccumulationDimension.Regular).value, previousPresent, previous)
    check(current.effectContext(AccumulationDimension.Regular).value, regularPresent, regular)
    check(current.effectContext(AccumulationDimension.Exceptional).value, exceptionalPresent, exceptional)

## Defaults and invalid dimensions refuse without fabricating contexts, initial sources or yield values.
proc refusals() =
  let invalid = default(AccumulationEffects)
  let context = default(AccumulationEffectContext)
  assert prepareAccumulationEffects(default(PreparedAccumulationContexts)).error ==
      AccumulationEffectError.InvalidContexts
  assert invalid.effectsSource.error == AccumulationEffectError.Uninitialized
  assert invalid.effectContext(AccumulationDimension.Regular).error ==
      AccumulationEffectError.Uninitialized
  assert context.effectInfo.error == AccumulationEffectError.Uninitialized
  assert context.effectInitialContext.error == AccumulationEffectError.Uninitialized
  assert context.effectYield.error == AccumulationEffectError.Uninitialized
  assert recordAccumulationYield(invalid, default(OutputCommitment)).error ==
      AccumulationEffectError.Uninitialized
  assert checkpointAccumulationEffects(invalid).error == AccumulationEffectError.Uninitialized
  let valid = prepareAccumulationEffects(preparedEffectContexts()).value
  assert valid.effectContext(cast[AccumulationDimension](2)).error ==
      AccumulationEffectError.InvalidDimension
  assert valid.effectContext(cast[AccumulationDimension](-1)).error ==
      AccumulationEffectError.InvalidDimension

## Independent immutable versions and refusal results release every acyclic pair/context reference.
proc lifetime() =
  let source = preparedEffectContexts()
  let hash = commitment(3)
  discard prepareAccumulationEffects(source)
  let before = getOccupiedMem()
  # No version links back to its parent pair; dropping these local versions releases the whole effect chain.
  for i in 0..<1000:
    let initial = prepareAccumulationEffects(source).value
    let yielded = recordAccumulationYield(initial, hash).value
    let checkpoint = checkpointAccumulationEffects(yielded).value
    let replaced = recordAccumulationYield(checkpoint, default(OutputCommitment)).value
    assert array[32, byte](replaced.effectContext(
        AccumulationDimension.Exceptional).value.effectYield.value) == array[32, byte](hash)
    assert prepareAccumulationEffects(default(PreparedAccumulationContexts)).error ==
        AccumulationEffectError.InvalidContexts
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_effects", 1000, before, after)

# All assertions run natively; retained children remain valid after construction locals have left scope.
let retained = versions()
check(retained, true, commitment(7))
history()
refusals()
lifetime()
echo "PASS accumulation effects: yield, checkpoint snapshots, credited provenance, guards and ARC"
