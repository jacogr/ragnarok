# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_provision_integration_arc_release"}

## Explicit context union and posterior fulfillment witnesses; no terminal-selection or whole-block certificate is fabricated.
## Covers canonical set semantics, resource preflight, exact writes, rollback, ownership and ARC release.

import std/[assertions, syncio]
import ../../../src/state/[accumulation_provisions, accumulation_effects, accumulation_context,
    preimages, store]
import ../../../src/codec/[bounded, composite, owned, header, state_accounts, state_requests,
  state_service_values, state_layout, state_trie]
import ../../../src/crypto/primitives
import ../../support/[accumulation_provision_integration, pvm_accumulation_provision, arc_evidence]
import ../../../src/state/accumulation_dispatch
import ../../../src/pvm/step

## Inject backend refusal only after source maps and expected keys have been prepared.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Permit bounded namespace work before a late key/root refusal.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

## Compare the complete-map commitment retained by one initialized store; no partial-map reconstruction is used.
proc root(state: StateStore): array[32, byte] = array[32, byte](
    state.snapshot.value.commitment.root)

## Full expected map updates use literal singleton-history bytes, independently from the integration operation.
proc expectedEntries(slot: uint32): seq[StateEntry] =
  result = integrationEntries()
  var history = @[1'u8]
  for offset in 0..<4: history.add(byte((slot shr (8*offset)) and
      255)) # Literal count + E4 slot, including uint32-max.
  let services = [42'u32, 42'u32, 42'u32, 99'u32]
  let blobs = @[newSeq[byte](0), @[2'u8], @[2'u8, 0], @[9'u8, 8, 7]]
  for index in 0..<services.len:
    let key = integrationRequest(services[index], blobs[index]).key
    for row in 0..<result.len:
      if array[31, byte](result[row].key) == array[31, byte](key):
        result[row].value = history # Replace only the four expected outstanding histories.
    let hash = ServicePreimageHash(array[32, byte](blake2b256(blobs[index]).value))
    result.add(servicePreimageEntry(ServiceIndex(services[index]), hash, blobs[index],
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(blobs[index].len))).value)

let contexts = integrationContexts()
let exact = integrationPolicy(contexts = 3, items = 8, perBlob = 3, total = 10, encoded = 27)
let plan = prepareAccumulationProvisions(contexts, exact).value
let info = plan.provisionPlanInfo.value
assert info.contexts == 3 and info.inputItems == 8 and info.items == 4
assert uint64(info.inputBytes) == 10 and uint64(info.bytes) == 6
for index in 0..<3:
  let selected = plan.provisionSourceAt(AccumulationProvisionSourceIndex(uint64(index))).value
  assert selected.effectInfo.value.provisions == (if index == 1: 2 else: 3)
assert plan.provisionSourceAt(AccumulationProvisionSourceIndex(3)).error ==
    AccumulationProvisionError.InvalidIndex
assert plan.provisionSourceAt(AccumulationProvisionSourceIndex(high(uint64))).error ==
    AccumulationProvisionError.InvalidIndex
for limits in [integrationPolicy(contexts = 2), integrationPolicy(items = 7), integrationPolicy(
    perBlob = 2), integrationPolicy(total = 9), integrationPolicy(encoded = 26)]:
  # Each independently short traversal/copy/wire ceiling refuses the whole union, including repeated A contributions.
  assert prepareAccumulationProvisions(contexts, limits).error ==
      AccumulationProvisionError.LimitExceeded
let emptyPlan = prepareAccumulationProvisions([], integrationPolicy(contexts = 0, items = 0,
  perBlob = 0, total = 0, encoded = 1)).value
assert emptyPlan.provisionPlanInfo.value.items == 0
assert prepareAccumulationProvisions([], integrationPolicy(encoded = 0)).error ==
    AccumulationProvisionError.LimitExceeded
let invalidContext = prepareAccumulationProvisions([default(AccumulationEffectContext)],
    integrationPolicy())
assert invalidContext.error == AccumulationProvisionError.InvalidContext
assert default(PreparedAccumulationProvisions).provisionPlanInfo.error ==
    AccumulationProvisionError.Uninitialized
assert default(PreparedAccumulationProvisions).provisionSourceAt(AccumulationProvisionSourceIndex(
    0)).error == AccumulationProvisionError.Uninitialized
var invalid = default(StateStore)
assert integrateAccumulationProvisions(invalid, plan, HeaderSlot(7)).error ==
    AccumulationProvisionError.InvalidState
let entries = integrationEntries()
for slot in [0'u32, 7'u32, high(uint32)]:
  # Literal whole-map expectations distinguish post-accumulation balances/storage from retained source accounts.
  var state = newStateStore(entries, integrationStoreLimits()).value
  let expected = newStateStore(expectedEntries(slot), integrationStoreLimits()).value
  let done = integrateAccumulationProvisions(state, plan, HeaderSlot(slot))
  assert done.error == AccumulationProvisionError.None
  assert root(state) == root(expected)
  assert array[32, byte](done.value.commitment.root) == root(expected)
  let priorRoot = root(state)
  failHash(1)
  let repeated = integrateAccumulationProvisions(state, plan, HeaderSlot(123))
  let empty = integrateAccumulationProvisions(state, emptyPlan, HeaderSlot(123))
  failHash(0)
  assert repeated.error == AccumulationProvisionError.None and empty.error ==
      AccumulationProvisionError.None
  assert root(state) == priorRoot # Cached identities and nonempty histories make repeated application a no-hash no-op.
for order in [@[contexts[0], contexts[1]], @[contexts[1], contexts[0]], @[contexts[2], contexts[1],
    contexts[0]]]:
  # Set results depend on exact pairs rather than source order or how often a context is retained.
  var state = newStateStore(entries, integrationStoreLimits()).value
  let chosen = prepareAccumulationProvisions(order, integrationPolicy()).value
  assert integrateAccumulationProvisions(state, chosen, HeaderSlot(7)).error ==
      AccumulationProvisionError.None
  assert root(state) == root(newStateStore(expectedEntries(7), integrationStoreLimits()).value)
for mode in 0..<3:
  var state = newStateStore(entries, integrationStoreLimits()).value
  let requests = [integrationRequest(42, @[]), integrationRequest(42, @[2'u8]), integrationRequest(
      42, @[2'u8, 0])]
  if mode == 0:
    # A service removed after provide makes all of that service's still-present request records irrelevant.
    discard state.apply([StateWrite(key: chapterServiceKey(StateChapter(255), ServiceIndex(42)),
        kind: StateWriteKind.Delete)]).value
  elif mode == 1:
    # Explicit cancellation drops the request, never creating a history or preimage from orphaned provision data.
    var writes: seq[StateWrite] = @[]
    for request in requests: writes.add(StateWrite(key: request.key, kind: StateWriteKind.Delete))
    discard state.apply(writes).value
  else:
    # Already supplied histories retain their old timestamps and do not get overwritten by a later candidate slot.
    var writes: seq[StateWrite] = @[]
    for request in requests: writes.add(StateWrite(key: request.key, kind: StateWriteKind.Put,
        value: @[1'u8, 5, 0, 0, 0]))
    discard state.apply(writes).value
  assert integrateAccumulationProvisions(state, plan, HeaderSlot(7)).error ==
      AccumulationProvisionError.None
  let snapshot = state.snapshot.value
  for bytes in [newSeq[byte](0), @[2'u8], @[2'u8, 0]]:
    let hash = ServicePreimageHash(array[32, byte](blake2b256(bytes).value))
    assert snapshot.lookup(servicePreimageKey(ServiceIndex(42), hash, ByteLimit(32)).value).error ==
        StateStoreError.MissingKey
  let otherHash = ServicePreimageHash(array[32, byte](blake2b256(@[9'u8, 8, 7]).value))
  assert snapshot.lookup(servicePreimageKey(ServiceIndex(99), otherHash, ByteLimit(
      32)).value).value.bytes == @[9'u8, 8, 7]
var malformed = newStateStore(entries, integrationStoreLimits()).value
let last = integrationRequest(99, @[9'u8, 8, 7])
discard malformed.apply([StateWrite(key: last.key, kind: StateWriteKind.Put, value: @[4'u8])]).value
let malformedRoot = root(malformed)
assert integrateAccumulationProvisions(malformed, plan, HeaderSlot(7)).error ==
    AccumulationProvisionError.MalformedState
assert root(malformed) == malformedRoot # A late corrupt request discards earlier prepared writes.
for limits in [integrationStoreLimits(writes = 7), integrationStoreLimits(bytes = 25)]:
  # Four pairs need eight writes and 26 total value bytes; one-short inherited policies publish nothing.
  var state = newStateStore(entries, limits).value
  let before = root(state)
  assert integrateAccumulationProvisions(state, plan, HeaderSlot(7)).error ==
      AccumulationProvisionError.LimitExceeded
  assert root(state) == before
for allowed in [0, 1, 7, 8]:
  var state = newStateStore(entries, integrationStoreLimits()).value
  let before = root(state)
  hashAfter(cint(allowed))
  let failed = integrateAccumulationProvisions(state, plan, HeaderSlot(7))
  failHash(0)
  assert failed.error == AccumulationProvisionError.BackendFailure
  assert root(state) == before # Includes late namespace refusal and final-root refusal after all eight namespace hashes.
failHash(1)
let failedPlan = prepareAccumulationProvisions(contexts, exact)
failHash(0)
assert failedPlan.error == AccumulationProvisionError.BackendFailure
## Return a plan after all temporary context handles are released, retaining exact source children privately.
proc detached(): PreparedAccumulationProvisions =
  let sources = integrationContexts()
  prepareAccumulationProvisions(sources, integrationPolicy()).value
let detachedPlan = detached()
assert detachedPlan.provisionSourceAt(AccumulationProvisionSourceIndex(
    1)).value.effectInfo.value.provisions == 2
var borrowed = @[contexts[0], contexts[1], contexts[2]]
let captured = prepareAccumulationProvisions(borrowed, integrationPolicy()).value
borrowed[0] = default(AccumulationEffectContext)
assert captured.provisionSourceAt(AccumulationProvisionSourceIndex(
    0)).value.effectInfo.value.provisions == 3
var copiedInfo = captured.provisionPlanInfo.value
copiedInfo.items = 999
assert captured.provisionPlanInfo.value.items == 4
let shared = prepareAccumulationProvisions(integrationContexts(true), integrationPolicy()).value
assert shared.provisionPlanInfo.value.items == 4 and uint64(shared.provisionPlanInfo.value.bytes) == 4
var sharedStore = newStateStore(entries, integrationStoreLimits()).value
assert integrateAccumulationProvisions(sharedStore, shared, HeaderSlot(7)).error ==
    AccumulationProvisionError.None
let sharedHash = ServicePreimageHash(array[32, byte](blake2b256(@[2'u8]).value))
for service in [42'u32, 99'u32]:
  # Equal bytes with different targets are separate members, even though the content hash is identical.
  assert sharedStore.snapshot.value.lookup(servicePreimageKey(ServiceIndex(service), sharedHash,
      ByteLimit(32)).value).value.bytes == @[2'u8]
let numeric = prepareAccumulationProvisions(integrationNumericContexts(), integrationPolicy()).value
var numericEntries = entries
for service in [1'u32, 256'u32]:
  numericEntries.add(serviceMetadataEntry(ServiceIndex(service), default(ServiceMetadata),
      ByteLimit(ServiceMetadataBytes)).value)
  numericEntries.add(integrationRequest(service, @[
      2'u8])) # Posterior target map is explicit and independent of the contexts' source.
var numericStore = newStateStore(numericEntries, integrationStoreLimits()).value
assert integrateAccumulationProvisions(numericStore, numeric, HeaderSlot(7)).error ==
    AccumulationProvisionError.None
for service in [1'u32, 256'u32]:
  assert numericStore.snapshot.value.lookup(servicePreimageKey(ServiceIndex(service), sharedHash,
      ByteLimit(32)).value).value.bytes == @[2'u8]
let guest = runProvision(provisionMachine([ProvisionGuestCall(id: 27, r7: high(uint64), r8: 65536, r9: 3)]))
assert guest.error == AccumulationDispatchError.None and guest.value.exit == StepExit.Halt
let guestPlan = prepareAccumulationProvisions([guest.effects.effectContext(
    AccumulationDimension.Regular).value], integrationPolicy()).value
var guestStore = newStateStore(entries, integrationStoreLimits()).value
assert integrateAccumulationProvisions(guestStore, guestPlan, HeaderSlot(7)).error ==
    AccumulationProvisionError.None
let guestHash = ServicePreimageHash(array[32, byte](blake2b256(@[9'u8, 8, 7]).value))
assert guestStore.snapshot.value.lookup(servicePreimageKey(ServiceIndex(42), guestHash, ByteLimit(
    32)).value).value.bytes == @[9'u8, 8, 7]
assert integrateAccumulationProvisions(guestStore, default(PreparedAccumulationProvisions),
    HeaderSlot(7)).error == AccumulationProvisionError.Uninitialized
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Fresh plans, successful publication, late backend refusal and replay all release acyclic retained owners.
  failHash(1)
  let refused = prepareAccumulationProvisions(contexts, exact)
  failHash(0)
  assert refused.error == AccumulationProvisionError.BackendFailure
  let current = prepareAccumulationProvisions(contexts, exact).value
  var state = newStateStore(entries, integrationStoreLimits()).value
  hashAfter(8)
  let failed = integrateAccumulationProvisions(state, current, HeaderSlot(7))
  failHash(0)
  assert failed.error == AccumulationProvisionError.BackendFailure
  assert integrateAccumulationProvisions(state, current, HeaderSlot(7)).error ==
      AccumulationProvisionError.None
  failHash(1)
  let repeated = integrateAccumulationProvisions(state, current, HeaderSlot(9))
  failHash(0)
  assert repeated.error == AccumulationProvisionError.None
let after = getOccupiedMem()
assert before == after
recordArcRelease("accumulation_provision_integration", 1000, before, after)
echo "Accumulation provision integration passed"
echo "ARC_RELEASE cycles=1000 unchanged"
