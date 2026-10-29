# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent rooted sources and arbitrary-precision expectations qualify complete prepared supervision/economic reports.
import std/[assertions, envvars, strutils, syncio]
import ../../support/[state_complete_serialization_context, state_inventory_context, economic_profile_context]
import ../../../src/chain/parameters
import ../../../src/state/[checkpoint, store, manifest, global_snapshot, validated_checkpoint, inventory]
import ../../../src/state/account/audit/plan as account_audit_plan
import ../../../src/state/account/review/plan as account_review_plan
import ../../../src/state/account/review as account_review
import ../../../src/state/footprint_audit
import ../../../src/state/preimage/[content as preimage_content, linkage as preimage_linkage]
import ../../../src/state/[economic_profile, economics_table, supervision_table]
import ../../../src/state/service/[directory as service_directory, deposit as service_deposit]
import ../../../src/state/account/deposit as account_deposit
import ../../../src/codec/bounded
import ../../../src/codec/state/[trie as state_trie, composition as state_composition]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Preparation is tested while content hashing is unavailable.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Successful execution hashes each original preimage exactly once.
const
  mapLimits = StateTrieLimits(items: ElementLimit(64), nodes: TrieNodeLimit(4096),
      perValue: ByteLimit(65536), totalValueBytes: ByteLimit(262144))
  limits = StateCheckpointLimits(checkpointBytes: ByteLimit(524288), store: StateStoreLimits(
      trie: mapLimits, writes: ElementLimit(64), writeValueBytes: ByteLimit(262144)),
      globals: GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
      maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144)), manifest: StateManifestLimits(
      services: ElementLimit(4), serialized: mapLimits, storageKeyBytes: ByteLimit(65)))
  policy = AccountReviewPlanLimits(audit: AccountAuditLimits(planning: ElementLimit(12),
      footprints: FootprintAuditLimits(services: ElementLimit(4), checks: ElementLimit(12)),
      content: PreimageContentLimits(services: ElementLimit(4), preimages: ElementLimit(4),
      perValue: ByteLimit(65), totalBytes: ByteLimit(260)), linkage: PreimageLinkageLimits(
      services: ElementLimit(4), preimages: ElementLimit(4), comparisons: ElementLimit(16))),
      directory: ServiceDirectoryLimits(services: ElementLimit(4), comparisons: ElementLimit(120),
      bytes: ByteLimit(4096)), supervision: SupervisionTableLimits(services: ElementLimit(4),
      bytes: ByteLimit(4096)), economics: EconomicsTableLimits(services: ElementLimit(4),
      bytes: ByteLimit(4096)))
proc words(text: string): seq[uint64] =
  ## Decode only complete fixed-width test observations; fixture parsing failure is never a passing assertion.
  let bytes = serializationOctets(text)
  assert bytes.len mod 8 == 0
  result = newSeq[uint64](bytes.len div 8)
  for i in 0..<result.len:
    var value = 0'u64
    for j in 0..<8: value = value or (uint64(bytes[8*i+j]) shl (8*j))
    result[i] = value
proc check(row: seq[uint64], singles, multiples: seq[string]): bool =
  ## Original and reverse declarations share an independently committed complete map, not an expected value generated natively.
  fail(0)
  let mode = int(row[0])
  let index = int(row[1])
  var services: seq[StateService] = @[]
  if mode == 0:
    services.add(serializationService(index))
  else:
    for i in 0..<4:
      let ordinal = if mode == 1: i else: 3-i
      services.add(serializationService(4*index+ordinal))
  let input = serializationOctets(if mode == 0: singles[index] else: multiples[index])
  var root = default(array[32, byte])
  for i in 0..<32: root[i] = input[25+i]
  let restored = decodeValidatedCheckpoint(input, StateRoot(root), services, inventoryProfile, limits).value
  let source = captureStateInventory(restored, services, inventoryCaptureLimits).value
  let profile = captureEconomicProfile(decodeParameters(economicTestWire(row[2], row[3], row[
      4])).value).value
  fail(1)
  let planned = planAccountReview(source, profile, policy)
  assert calls() == 0
  if row[6] == 0:
    assert planned.error == AccountReviewPlanError.EconomicsFailure
    let reason = planned.economicsFailure
    assert reason.error == EconomicsTableError.ObservationFailure
    assert uint64(reason.failedOrdinal) == row[7] and uint64(reason.failedService) == row[8]
    assert reason.observationFailure.error == ServiceDepositError.ArithmeticFailure
    assert reason.observationFailure.arithmeticError == AccountDepositError.Overflow
    return false # No content hash or prefix report escapes an early/late mathematical refusal.
  assert planned.error == AccountReviewPlanError.None
  fail(0)
  let completed = executeAccountReview(planned.value).value
  assert uint64(calls()) == row[5]
  assert sameStateInventory(completed.reviewInventory.value, source)
  assert sameEconomicProfile(completed.reviewEconomicProfile.value, profile)
  let economics = completed.reviewEconomics.value
  let supervision = completed.reviewSupervision.value
  var covered = 0
  for i in 0..<int(row[5]):
    let ordinal = InventoryServiceIndex(uint64(i))
    let economic = economics.economicTableAt(ordinal).value
    let supervisor = supervision.supervisionTableAt(ordinal).value
    let start = 9+5*i
    assert uint64(economic.service) == row[start] and uint64(economic.minimum) == row[start+1]
    assert economic.covered == (row[start+2] == 1)
    assert uint64(supervisor.effective) == row[start+3] and uint64(ord(supervisor.decision)) == row[start+4]
    if economic.covered: inc covered # Completed whole-report counts must match every independently predicted row.
  assert economics.economicTableInfo.value.covered == covered
  assert economics.economicTableInfo.value.uncovered == services.len-covered
  true
proc main() {.raises.} =
  ## All fixture inputs are SHA-verified by the native runner before these independent reports execute.
  let singles = readFile(getEnv("RAGNAROK_COMPLETE_SERIALIZATION")).splitLines()
  let multiples = readFile(getEnv("RAGNAROK_MULTISERVICE_SERIALIZATION")).splitLines()
  var count = 0
  var succeeded = 0
  for line in readFile(getEnv("RAGNAROK_COMPLETE_REVIEW")).splitLines():
    if line.len == 0: continue # The pinned fixture terminates with a newline.
    if check(words(line), singles, multiples): inc succeeded
    inc count
  assert count == 192 and succeeded > 0 and succeeded < count
  fail(0)
  echo "state-complete-review-corpus: ok (192 cases)"
try:
  main()
except:
  quit(2) # Failed restoration/setup cannot qualify report observations or no-hash preparation.
