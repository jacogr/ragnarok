# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine preimage addition, current-service raw storage deletion and empty-junior ejection refuse identity-preserving continuation with the exact physical key.
# @@Verification={"arc":"state_current_identity_changes_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_namespace_transition_context, current_namespace_execution_context,
    current_namespace_context, service_namespace_seed, accumulation_execution_context,
    current_identity_context, arc_evidence]
import ../../../src/state/[current_identities, accumulation_current_update, store]
import ../../../src/codec/[bounded, report_owned, state_accounts, state_composition, state_requests,
    state_service_values, state_layout]
import ../../../src/crypto/primitives
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Original full matching and genuine actual mutation execution precede hash-free identity refusal observation.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Complete physical key comparison and selected refusal key copy cannot hash.
proc verify(fixture: CurrentNamespaceTransition, key: StateKey, error: CurrentIdentityError) =
  ## Only actual producer-added/removed physical identities select the corresponding guarded reason key.
  let refused = preserveCurrentIdentities(fixture.parent, fixture.update, currentIdentityTestLimits)
  assert refused.error == error
  assert array[31, byte](refused.refusedIdentity) == array[31, byte](key)
proc cycle(added, deleted, ejected: CurrentNamespaceTransition, preimage, storage,
    metadata: StateKey) =
  ## Retire admitted view/index copies and actual refusal observations without retaining partial continuation owners.
  verify(added, preimage, CurrentIdentityError.NewIdentity)
  verify(deleted, storage, CurrentIdentityError.MissingIdentity)
  verify(ejected, metadata, CurrentIdentityError.MissingIdentity)
proc main() {.raises.} =
  ## Every header/root/signature and current update comes from original code/namespace inputs and actual current candidate execution.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let halt = namespaceHaltCode()
  let blob = @[88'u8, 89, 90]
  let digest = ServicePreimageHash(array[32, byte](blake2b256(blob).value))
  var options = executionFixtureConfig()
  options.firstProgram = halt
  options.secondProgram = halt
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  options.signed.serviceNamespaces[1].requests.add(StateRequestItem(hash: digest,
      length: RequestLength(3), history: requestedHistory()))
  options.signed.preimageWire = @[1'u8, 99, 0, 0, 0, 3, 88, 89, 90]
  let added = namespaceTransitionFixture(base, options)
  let preimage = servicePreimageKey(ServiceIndex(99), digest, ByteLimit(32)).value
  assert added.update.currentUpdateState.lookup(preimage).value.bytes == blob
  options = executionFixtureConfig()
  options.firstProgram = halt
  options.secondProgram = namespaceStorageCode(@[])
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  options.signed.serviceNamespaces[1].storage[1] = StateStorageItem(key: @[7'u8], value: @[13'u8, 14, 15])
  let deleted = namespaceTransitionFixture(base, options)
  let storage = serviceStorageKey(ServiceIndex(99), [7'u8], ByteLimit(1)).value
  assert deleted.update.currentUpdateState.lookup(storage).error == StateStoreError.MissingKey
  options = executionFixtureConfig()
  options.firstProgram = namespaceEjectCode()
  options.secondProgram = halt
  options.second = ExecutionEnding.Missing
  options.secondBalance = 0
  options.secondSupervisor = 42
  let initial = namespaceSeeds()
  options.signed.serviceNamespaces = @[initial[0], ServiceNamespaceSeed(service: ServiceIndex(99),
      storage: @[], preimages: @[], requests: @[])]
  let ejected = namespaceTransitionFixture(base, options, ElementLimit(1))
  let metadata = chapterServiceKey(StateChapter(255), ServiceIndex(99))
  assert ejected.update.currentUpdateState.lookup(metadata).error == StateStoreError.MissingKey
  fail(1)
  cycle(added, deleted, ejected, preimage, storage, metadata)
  assert calls() == 0
  for i in 0..<25: cycle(added, deleted, ejected, preimage, storage, metadata)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(added, deleted, ejected, preimage, storage, metadata)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_current_identity_changes", 1000, before, finalBytes)
  fail(0)
  echo "state-current-identity-changes: ok"
try:
  main()
except:
  quit(2) # No hand-edited prepared result or projected map can substitute an actual signed current identity change.
