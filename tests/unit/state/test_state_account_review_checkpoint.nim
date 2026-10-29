# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit-root restored reviews preserve phase refusal, selected parameters, detached input and composite owner retirement.
# @@Verification={"arc": "state_account_review_checkpoint_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, account_review_checkpoint_context,
    economic_profile_context, arc_evidence]
import ../../../src/chain/parameters
import ../../../src/state/account/review/checkpoint as account_review_checkpoint
import ../../../src/state/account/review as account_review
import ../../../src/state/planned/account_checkpoint as planned_account_checkpoint
import ../../../src/state/[validated_checkpoint, checkpoint, store, manifest, inventory, economic_profile]
import ../../../src/state/service/directory as service_directory
import ../../../src/state/[footprint_audit, supervision_table, economics_table]
import ../../../src/state/service/deposit as service_deposit
import ../../../src/state/account/deposit as account_deposit
import ../../../src/codec/bounded
import ../../../src/codec/state/[trie as state_trie, accounts as state_accounts,
    composition as state_composition]
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset observer counters and optionally reject all hashes.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Missing economic policy must refuse before restoration hashing.
proc cycle(wire: seq[byte], root: StateRoot, services: seq[StateService],
    profile: StateEconomicProfile) =
  ## Retire complete restored mappings, audit certificates, directories and fixed observation tables.
  let completed = decodeAccountReviewCheckpoint(wire, root, services, inventoryProfile, profile,
      accountReviewCheckpointTestLimits).value
  assert completed.accountReviewInfo.value.economics.uncovered == 1
proc main() {.raises.} =
  ## Independent source includes an undercovered account, which remains a successful explicit observation.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  services[0].metadata.balance = AccountBalance(100)
  let source = inventoryManifest(fixture, services).manifestSource.value
  let root = source.commitment.root
  let wire = encodeFullCheckpoint(source, accountReviewCheckpointTestLimits.checkpoint.serialization.checkpointBytes).value
  let profile = captureEconomicProfile(decodeParameters(economicTestWire()).value).value
  let overflow = captureEconomicProfile(decodeParameters(economicTestWire(0, 0, high(
      uint64))).value).value
  fail(1)
  let missingPolicy = decodeAccountReviewCheckpoint(wire, root, services, inventoryProfile, default(
      StateEconomicProfile), accountReviewCheckpointTestLimits)
  assert missingPolicy.error == AccountReviewCheckpointError.InvalidProfile and calls() == 0
  fail(0)
  var disposable = newSeq[byte](wire.len)
  for i in 0..<wire.len: disposable[i] = wire[i] # Use a unique caller buffer with no retained external byte alias.
  let completed = decodeAccountReviewCheckpoint(disposable, root, services, inventoryProfile,
      profile, accountReviewCheckpointTestLimits).value
  for i in 0..<disposable.len: disposable[i] = 0 # Destroy borrowed framing and payload bytes after synchronous completion.
  disposable = @[]
  assert completed.accountReviewInfo.value.economics.uncovered == 1
  assert sameEconomicProfile(completed.reviewEconomicProfile.value, profile)
  let retained = completed.reviewInventory.value.inventorySource.value.manifestSource.value
  assert not sameStateSnapshot(retained, source)
  assert encodeFullCheckpoint(retained, accountReviewCheckpointTestLimits.checkpoint.serialization.checkpointBytes).value == wire
  var wrong = array[32, byte](root)
  wrong[0] = wrong[0] xor 1
  let untrusted = decodeAccountReviewCheckpoint(wire, StateRoot(wrong), services, inventoryProfile,
      profile, accountReviewCheckpointTestLimits)
  assert untrusted.error == AccountReviewCheckpointError.CheckpointFailure
  assert untrusted.checkpointFailure.serializationFailure.checkpointError ==
      CheckpointError.RootMismatch
  var short = accountReviewCheckpointTestLimits
  short.directory.services = ElementLimit(1)
  let directory = decodeAccountReviewCheckpoint(wire, root, services, inventoryProfile, profile, short)
  assert directory.error == AccountReviewCheckpointError.DirectoryFailure
  assert directory.directoryFailure.error == ServiceDirectoryError.LimitExceeded
  short = accountReviewCheckpointTestLimits
  short.footprints.checks = ElementLimit(3)
  let footprint = decodeAccountReviewCheckpoint(wire, root, services, inventoryProfile, profile, short)
  assert footprint.error == AccountReviewCheckpointError.FootprintFailure
  assert footprint.footprintFailure.error == FootprintAuditError.LimitExceeded
  short = accountReviewCheckpointTestLimits
  short.supervision.services = ElementLimit(1)
  let supervision = decodeAccountReviewCheckpoint(wire, root, services, inventoryProfile, profile, short)
  assert supervision.error == AccountReviewCheckpointError.SupervisionFailure
  assert supervision.supervisionFailure.error == SupervisionTableError.LimitExceeded
  short = accountReviewCheckpointTestLimits
  short.economics.services = ElementLimit(1)
  let economics = decodeAccountReviewCheckpoint(wire, root, services, inventoryProfile, profile, short)
  assert economics.error == AccountReviewCheckpointError.EconomicsFailure
  assert economics.economicsFailure.error == EconomicsTableError.LimitExceeded
  let arithmetic = decodeAccountReviewCheckpoint(wire, root, services, inventoryProfile, overflow, accountReviewCheckpointTestLimits)
  assert arithmetic.error == AccountReviewCheckpointError.EconomicsFailure
  assert arithmetic.economicsFailure.observationFailure.arithmeticError ==
      AccountDepositError.Overflow
  for i in 0..<25: cycle(wire, root, services, profile) # Warm the complete restoration/review graph.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(wire, root, services, profile) # No restored source or table owners accumulate across retirement.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_account_review_checkpoint", 1000, before, finalBytes)
  echo "state-account-review-checkpoint: ok"
try:
  main()
except:
  quit(2) # Setup failure cannot qualify explicit policy/root or retained ownership evidence.
