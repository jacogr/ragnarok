# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native provide state-effect witnesses: requested target/blob ownership, checkpoint retention and bounded work.
## Hastur entry point covers protocol/local refusals, exact bytes, unchanged state, result guards and ARC release.

# @@Verification={"arc": "accumulation_provisions_arc_release"}

import std/[assertions, syncio]
import ../../../src/state/[accumulation_effects, accumulation_context, accumulation_invocation,
  accumulation_service, preimages, store]
import ../../../src/codec/[bounded, composite, state_outputs, state_accounts, state_requests,
  state_service_values, state_trie, state_layout]
import ../../../src/crypto/primitives
import ../../support/[accumulation_effect_context, arc_evidence]

## Refuse a specific hash after real source preparation; failures must never masquerade as HUH or successful capture.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Permit payload hashing, then refuse request-namespace derivation.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Count hash attempts to prove per-blob policy and missing targets preflight cryptographic work.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Keep tiny independent local ceilings; exact and one-short policies are exercised explicitly below.
proc policy(items = 6'u64, perBlob = 3'u64, total = 10'u64): AccumulationProvisionLimits =
  AccumulationProvisionLimits(items: ElementLimit(items), perBlob: ByteLimit(perBlob),
      totalBlobBytes: ByteLimit(total))

## Construct authored canonical namespace entries; independent existing codec/crypto corpora check these primitives.
proc request(service: ServiceIndex, bytes: seq[byte], history: seq[byte] = @[0'u8],
    lengthDelta = 0'u32): StateEntry =
  let digest = ServicePreimageHash(array[32, byte](blake2b256(bytes).value))
  let key = serviceRequestKey(service, digest, RequestLength(uint32(bytes.len)+lengthDelta),
      ByteLimit(32)).value
  StateEntry(key: key, value: history)

## Populate live self/other targets and all three requested blobs; account keys/requests stay in the complete map.
proc source(): AccumulationEffects =
  var entries = @[serviceMetadataEntry(ServiceIndex(99), ServiceMetadata(balance: AccountBalance(
      100)), ByteLimit(ServiceMetadataBytes)).value]
  # The same data requested by different services represents two distinct eligible provision pairs.
  for service in [ServiceIndex(42), ServiceIndex(99)]:
    for bytes in [@[9'u8, 8, 7], @[4'u8, 5], newSeq[byte](0)]:
      entries.add(request(service, bytes)) # Every request is canonical outstanding history, not present-empty raw state.
  prepareAccumulationEffects(preparedEffectContexts(entries)).value

## Extract copied current provision count; default contexts and owner-less lists cannot supply this fact.
proc count(effects: AccumulationEffects, dimension = AccumulationDimension.Regular): int =
  effects.effectContext(dimension).value.effectInfo.value.provisions

## Verify an owner-bound provision survives all parent owners and preserves its exact target and independent bytes.
proc check(provision: AccumulationProvision, service: uint32, bytes: seq[byte]) =
  assert uint32(provision.provisionInfo.value.service) == service
  assert provision.provisionInfo.value.bytes == bytes.len
  assert provision.copyProvisionBytes.value == bytes

## Provide/overwrite-yield/checkpoint histories preserve earlier sets, borrowed inputs and credited source state.
proc versions(): AccumulationProvision =
  let initial = source()
  let before = initial.effectsSource.value.initialContext(
      AccumulationDimension.Regular).value.contextAccounts.value
  let oldRoot = array[32, byte](before.commitment.root)
  var bytes = @[9'u8, 8, 7]
  let first = recordAccumulationProvision(initial, ServiceIndex(42), bytes, policy()).value
  bytes[0] = 0 # Caller mutation cannot change captured payload identity or a later checkpoint.
  let saved = checkpointAccumulationEffects(first).value
  let second = recordAccumulationProvision(saved, ServiceIndex(99), @[9'u8, 8, 7], policy()).value
  let yielded = recordAccumulationYield(second, default(OutputCommitment)).value
  let empty = recordAccumulationProvision(yielded, ServiceIndex(42), [], policy()).value
  assert initial.count == 0 and first.count == 1 and saved.count == 1 and second.count == 2
  assert empty.count == 3 and empty.count(AccumulationDimension.Exceptional) == 1
  assert empty.effectContext(AccumulationDimension.Regular).value.effectInfo.value.hasYield
  let context = empty.effectContext(AccumulationDimension.Regular).value
  check(context.effectProvisionAt(AccumulationProvisionIndex(0)).value, 42, @[9'u8, 8, 7])
  check(context.effectProvisionAt(AccumulationProvisionIndex(1)).value, 99, @[9'u8, 8, 7])
  check(context.effectProvisionAt(AccumulationProvisionIndex(2)).value, 42, @[])
  check(empty.effectContext(AccumulationDimension.Exceptional).value.effectProvisionAt(
      AccumulationProvisionIndex(0)).value, 42, @[9'u8, 8, 7])
  var copied = context.effectProvisionAt(AccumulationProvisionIndex(
      0)).value.copyProvisionBytes.value
  copied[0] = 255
  check(context.effectProvisionAt(AccumulationProvisionIndex(0)).value, 42, @[9'u8, 8, 7])
  let after = context.effectInitialContext.value.contextAccounts.value
  assert array[32, byte](after.commitment.root) == oldRoot
  assert after.lookup(request(ServiceIndex(42), @[9'u8, 8, 7]).key).value.bytes == @[0'u8]
  let account = after.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(42))).value
  assert uint64(decodeServiceMetadata(account.bytes, ByteLimit(
      ServiceMetadataBytes)).value.metadata.balance) == 17
  assert uint64(context.effectInitialContext.value.contextSelf.value.balance) == 17
  assert recordAccumulationProvision(first, ServiceIndex(42), @[9'u8, 8, 7], policy(1, 3,
      3)).error == AccumulationEffectError.AlreadyProvided
  let savedAgain = checkpointAccumulationEffects(empty).value
  assert savedAgain.count(AccumulationDimension.Exceptional) == 3
  assert saved.count(AccumulationDimension.Exceptional) == 1
  result = context.effectProvisionAt(AccumulationProvisionIndex(1)).value

## Missing/nonempty/malformed request histories and target accounts must select exact protocol/local refusals.
proc requests() =
  let bytes = @[9'u8, 8, 7]
  let initial = source()
  assert recordAccumulationProvision(initial, ServiceIndex(100), bytes, policy()).error ==
      AccumulationEffectError.UnknownService
  assert recordAccumulationProvision(initial, ServiceIndex(42), @[0'u8], policy()).error ==
      AccumulationEffectError.NotRequested
  let state = initial.effectContext(AccumulationDimension.Regular).value.effectInitialContext.value.contextAccounts.value
  let digest = ServicePreimageHash(array[32, byte](blake2b256(bytes).value))
  assert preimageRequested(state, ServiceIndex(42), digest, RequestLength(3)).value
  assert not preimageRequested(state, ServiceIndex(100), digest, RequestLength(3)).value
  assert not preimageRequested(state, ServiceIndex(42), digest, RequestLength(high(uint32))).value
  assert preimageRequested(default(StateStoreSnapshot), ServiceIndex(42), digest, RequestLength(
      3)).error == PreimageTransitionError.InvalidState
  # Target identity keeps the complete uint32 domain; low/reserved indices are not extra provide eligibility filters.
  for target in [ServiceIndex(0), ServiceIndex(high(uint32))]:
    let extra = @[serviceMetadataEntry(target, ServiceMetadata(), ByteLimit(
        ServiceMetadataBytes)).value, request(target, bytes)]
    let effects = prepareAccumulationEffects(preparedEffectContexts(extra)).value
    let provided = recordAccumulationProvision(effects, target, bytes, policy()).value
    check(provided.effectContext(AccumulationDimension.Regular).value.effectProvisionAt(
        AccumulationProvisionIndex(0)).value, uint32(target), bytes)
  # Each history uses the same exact key; complete canonical zero-slot history is the only accepted shape.
  for history in [newSeq[byte](0), @[1'u8, 1, 0, 0, 0], @[2'u8, 1, 0, 0, 0, 2, 0, 0, 0],
      @[3'u8, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0], @[0'u8, 0], @[128'u8, 0], @[4'u8], newSeq[byte](14)]:
    let extra = @[request(ServiceIndex(42), bytes, history)]
    let effects = prepareAccumulationEffects(preparedEffectContexts(extra)).value
    let observed = recordAccumulationProvision(effects, ServiceIndex(42), bytes, policy()).error
    if history.len == 5 or history.len == 9 or history.len == 13:
      assert observed == AccumulationEffectError.NotRequested # Available/removed/restored are not outstanding.
    else:
      assert observed == AccumulationEffectError.MalformedState # Raw empty, suffix, invalid count and oversized histories reject.
    assert effects.count == 0
  let wrongLength = prepareAccumulationEffects(preparedEffectContexts(@[request(ServiceIndex(42),
      bytes, lengthDelta = 1)])).value
  assert recordAccumulationProvision(wrongLength, ServiceIndex(42), bytes, policy()).error ==
      AccumulationEffectError.NotRequested
  let orphan = prepareAccumulationEffects(preparedEffectContexts(@[request(ServiceIndex(100),
      bytes)])).value
  assert recordAccumulationProvision(orphan, ServiceIndex(100), bytes, policy()).error ==
      AccumulationEffectError.UnknownService
  # Corrupt target metadata remains a local refusal rather than ordinary unknown/not-requested.
  for size in [104, 105, 106]:
    var malformed = newSeq[byte](size)
    if size == 105: malformed[0] = 1 # Exact width with an unsupported metadata version is still corrupt.
    let effects = prepareAccumulationEffects(preparedEffectContexts(@[
      StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(99)), value: malformed),
          request(ServiceIndex(99), bytes)])).value
    assert recordAccumulationProvision(effects, ServiceIndex(99), bytes, policy()).error ==
        AccumulationEffectError.MalformedState

## Count, individual and total-byte budgets preflight retaining/copying; hash failures never publish partial effects.
proc limitsAndFailures() =
  let initial = source()
  let bytes = @[9'u8, 8, 7]
  # Per-blob limits and absent targets refuse before any digest or namespace hashing.
  failHash(1)
  assert recordAccumulationProvision(initial, ServiceIndex(42), bytes, policy(1, 2, 3)).error ==
      AccumulationEffectError.LimitExceeded
  assert hashCalls() == 0
  assert recordAccumulationProvision(initial, ServiceIndex(100), bytes, policy()).error ==
      AccumulationEffectError.UnknownService
  assert hashCalls() == 0
  failHash(0)
  assert recordAccumulationProvision(initial, ServiceIndex(42), bytes, policy(0, 3, 3)).error ==
      AccumulationEffectError.LimitExceeded
  assert recordAccumulationProvision(initial, ServiceIndex(42), bytes, policy(1, 3, 2)).error ==
      AccumulationEffectError.LimitExceeded
  let exact = recordAccumulationProvision(initial, ServiceIndex(42), bytes, policy(1, 3, 3)).value
  assert exact.count == 1
  assert recordAccumulationProvision(exact, ServiceIndex(99), [], policy(2, 3, 3)).error ==
      AccumulationEffectError.None
  assert recordAccumulationProvision(exact, ServiceIndex(99), @[4'u8, 5], policy(2, 3, 4)).error ==
      AccumulationEffectError.LimitExceeded
  assert recordAccumulationProvision(exact, ServiceIndex(99), @[4'u8, 5], policy(2, 3, 5)).error ==
      AccumulationEffectError.None
  assert recordAccumulationProvision(exact, ServiceIndex(42), bytes, policy(0, 3, 3)).error ==
      AccumulationEffectError.LimitExceeded
  assert recordAccumulationProvision(exact, ServiceIndex(99), [], policy(2, 2, 3)).error ==
      AccumulationEffectError.LimitExceeded
  # Independently fail payload and request-key hashing; a failed provider cannot return HUH or mutate either dimension.
  for successful in 0..1:
    hashAfter(cint(successful))
    assert recordAccumulationProvision(initial, ServiceIndex(42), bytes, policy()).error ==
        AccumulationEffectError.BackendFailure
    failHash(0)
    assert initial.count == 0 and initial.count(AccumulationDimension.Exceptional) == 0
  assert default(AccumulationProvision).provisionInfo.error == AccumulationEffectError.Uninitialized
  assert default(AccumulationProvision).copyProvisionBytes.error ==
      AccumulationEffectError.Uninitialized
  let context = exact.effectContext(AccumulationDimension.Regular).value
  assert context.effectProvisionAt(AccumulationProvisionIndex(1)).error ==
      AccumulationEffectError.InvalidIndex
  assert context.effectProvisionAt(AccumulationProvisionIndex(high(uint64))).error ==
      AccumulationEffectError.InvalidIndex
  let refused = recordAccumulationProvision(default(AccumulationEffects), ServiceIndex(42), bytes,
      policy())
  assert refused.error == AccumulationEffectError.Uninitialized
  assert default(AccumulationEffectContext).effectProvisionAt(AccumulationProvisionIndex(
      0)).error == AccumulationEffectError.Uninitialized

## A fixed six-member model checks provision membership through interleaved provide/yield/checkpoint operations.
proc history() =
  var current = source()
  var regular = default(array[6, bool])
  var exceptional = default(array[6, bool])
  let services = [ServiceIndex(42), ServiceIndex(99), ServiceIndex(42), ServiceIndex(99),
      ServiceIndex(42), ServiceIndex(99)]
  let blobs = [@[9'u8, 8, 7], @[9'u8, 8, 7], @[4'u8, 5], @[4'u8, 5], newSeq[byte](0), newSeq[byte](0)]
  # The model uses only fixed membership bits; checkpoint copies them without mutable sequence aliasing.
  for step in 0..<96:
    if step mod 4 == 0:
      current = checkpointAccumulationEffects(current).value # Capture the exact current set.
      exceptional = regular
    elif step mod 4 == 1:
      current = recordAccumulationYield(current, default(
          OutputCommitment)).value # Yield must preserve provision sets.
    else:
      let index = step mod 6
      let changed = recordAccumulationProvision(current, services[index], blobs[index], policy())
      if regular[index]:
        assert changed.error == AccumulationEffectError.AlreadyProvided # Even a full set recognizes its duplicate members.
      else:
        assert changed.error == AccumulationEffectError.None
        current = changed.value
        regular[index] = true
    # Compare both selected dimensions against independent membership, including each raw target/blob identity.
    for dimension in [AccumulationDimension.Regular, AccumulationDimension.Exceptional]:
      let expected = if dimension == AccumulationDimension.Regular: regular else: exceptional # Only two valid dimensions.
      var seen = default(array[6, bool])
      let context = current.effectContext(dimension).value
      for ordinal in 0..<context.effectInfo.value.provisions:
        let provision = context.effectProvisionAt(AccumulationProvisionIndex(uint64(ordinal))).value
        var found = false
        for candidate in 0..<6:
          if uint32(provision.provisionInfo.value.service) == uint32(services[candidate]) and
              provision.copyProvisionBytes.value == blobs[candidate]:
            assert expected[candidate] and not seen[
                candidate] # No unsolicited or duplicate set member may appear.
            seen[candidate] = true
            found = true
        assert found
      assert seen == expected

## Accepted/rejected provision versions and retained payload copies release all acyclic ownership each cycle.
proc lifetime() =
  let initial = source()
  let bytes = @[9'u8, 8, 7]
  discard recordAccumulationProvision(initial, ServiceIndex(42), bytes, policy())
  let before = getOccupiedMem()
  # Old pair and provision owners are shared immutably, with no retained parent-version chains.
  for i in 0..<1000:
    let provided = recordAccumulationProvision(initial, ServiceIndex(42), bytes, policy()).value
    let saved = checkpointAccumulationEffects(provided).value
    let yielded = recordAccumulationYield(saved, default(OutputCommitment)).value
    assert yielded.count(AccumulationDimension.Exceptional) == 1
    assert recordAccumulationProvision(yielded, ServiceIndex(42), bytes, policy()).error ==
        AccumulationEffectError.AlreadyProvided
    check(yielded.effectContext(AccumulationDimension.Regular).value.effectProvisionAt(
        AccumulationProvisionIndex(0)).value, 42, bytes)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_provisions", 1000, before, after)

# Exercise all native assertions and keep one payload alive after every source/effect construction local is released.
let retained = versions()
check(retained, 99, @[9'u8, 8, 7])
requests()
limitsAndFailures()
history()
lifetime()
echo "PASS accumulation provisions: requested owned data, checkpoint sets, limits, refusals and ARC"
