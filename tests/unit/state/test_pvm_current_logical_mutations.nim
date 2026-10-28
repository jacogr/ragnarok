# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual collected storage identity creation/deletion refuses logical continuation before any host enqueue or durable publication.
import std/[assertions, envvars, syncio]
import std/posix/posix
import ../../support/[current_namespace_execution_context, current_application_context,
    current_logical_collection_context, accumulation_current_candidate_context,
    parent_profile_context, parent_globals_context, supplied_logical_context,
    current_identity_context, current_services_disk_samples, managed_storage_samples,
    pvm_accumulation_program]
import ../../../src/app/[services, options, current_block_input, current_handoff]
import ../../../src/chain/[provider, genesis]
import ../../../src/codec/[bounded, report_owned, state_accounts, state_service_values]
import ../../../src/state/[parent_profile, parent_globals, parent_logical, current_identities,
    accumulation_current_update, store, block_admission, report_admission]
import ../../../src/storage/managed_manifest
proc mutationCode(key: byte, value: seq[byte]): seq[byte] =
  ## Real write host appends an identity for absent key7, or removes existing key5 when the supplied value has zero length.
  var payload = @[key]
  for octet in value: payload.add(octet)
  let instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
      registerImmediate(9, 1), registerImmediate(10, 196609), registerImmediate(11, uint64(
          value.len)),
      @[10'u8, 5], @[50'u8, 0]]
  result = @[0'u8]
  for octet in guestEnvelope(instructions, payload): result.add(octet)
proc scenario(fixture: NamespaceExecutionFixture, layout: int, added: bool) {.raises.} =
  ## The exact configured owner seeds State before genuine native execution; identity refusal must leave this canonical/durable parent unmodified.
  var path = "pvm-current-logical-mutation-chain"
  var database = "pvm-current-logical-mutation-state-" & $layout
  writeFile(path, fixture.parent.bestBlock.value.currentApplicationText)
  defer:
    discard posix.unlink(path.toCString())
    if layout == 2: removeManagedSample(database, [ManagedEpoch(1)])
    elif layout == 1: discard posix.unlink(database.toCString())
  var options = default(Options)
  if layout == 0:
    assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  else: options = currentDiskOptions(path, database, layout == 2, 0)
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(options, "logical mutation refusal")
  let before = owner.stateSnapshot.value
  let profile = captureParentProfile(owner.chainView, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  let declarations = fixture.executableNamespaceServices(before)
  let parent = captureLogicalParent(globals, declarations, suppliedLogicalTestLimits).value
  let child = fixture.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let update = owner.collectLogicalChild(input, child, currentCandidateLimits())
  let key = serviceStorageKey(ServiceIndex(99), @[if added: 7'u8 else: 5'u8], ByteLimit(1)).value
  if added:
    assert before.lookup(key).error == StateStoreError.MissingKey
    assert update.currentUpdateState.lookup(key).value.bytes == @[21'u8, 22]
  else:
    assert before.lookup(key).error == StateStoreError.None and before.lookup(
        key).value.bytes.len == 0
    assert update.currentUpdateState.lookup(key).error == StateStoreError.MissingKey
  let refused = preserveCurrentIdentities(parent, update, currentIdentityTestLimits)
  let expected = if added: CurrentIdentityError.NewIdentity else: CurrentIdentityError.MissingIdentity
  assert refused.error == expected
  assert array[31, byte](refused.refusedIdentity) == array[31, byte](key)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  assert not owner.diskPublicationActive
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  assert owner.chainView.retainedCount == 1
  assert owner.preparationAvailable and owner.stateProofAvailable
  owner.close()
  if layout != 0:
    assert owner.start(options, "strict refused logical mutation restart")
    assert owner.chainView.retainedCount == 1
    equalCurrentDiskMap(owner.stateSnapshot.value, before)
    owner.close()
proc main() {.raises.} =
  ## Both genuinely executed mutations use complete signed original code/request/storage namespaces and funded existing service99.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let added = namespaceExecutionFixture(base, namespaceHaltCode(), mutationCode(7, @[21'u8, 22]))
  let deleted = namespaceExecutionFixture(base, namespaceHaltCode(), mutationCode(5, @[]))
  for layout in 0..2:
    scenario(added, layout, true)
    scenario(deleted, layout, false)
  echo "PVM current logical mutation refusals passed"
try:
  main()
except:
  quit(2) # An execution, exact identity refusal, host publication or strict durable-prefix mismatch is a hard failure.
