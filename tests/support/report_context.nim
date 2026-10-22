# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared deterministic report-policy test contexts; no production verifier or verdict is
## replaced.
##
## Exposes signed report-policy fixtures and trusted transport helpers shared by native report
## tests.

import std/[assertions, parseutils]
import ../../src/state/[report_policy, guarantee_credentials, guarantors, store]
import ../../src/codec/[guarantees, assurances, bounded, state_safrole, header,
  report_owned, owned, work_report, work_digest, composite, state_accounts,
  state_authorization, state_layout, state_trie]
import ../../src/crypto/[primitives, guarantee]
from ../../src/codec/disputes import OffenderKey

proc unhex*(text: string): seq[byte] =
  ## Decode trusted fixture transport exactly; a dash denotes an empty sequence only.
  if text == "-": return @[] # Empty transport is distinct from a fabricated state value.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    assert parseHex(text[i*2..i*2+1], result[i]) == 2 # Require complete octets.


proc credentialConfig*(cores: uint64): GuaranteeCredentialConfig =
  ## Configure both published populations without conflating roster size and active core count.
  GuaranteeCredentialConfig(assignments: GuarantorConfig(roster: ValidatorStateConfig(
    cores: CoreCount(cores), validators: ElementLimit(cores*3), maxBytes: ByteLimit(400000)),
    epochSlots: EpochSlots(if cores == 341: 600 else: 12),
    rotationSlots: GuarantorRotationSlots(if cores == 341: 10 else: 4), offenders: ElementLimit(
        cores*3)),
    maxBytes: ByteLimit(10000000), reporters: ElementLimit(cores*3))


proc policy*(cores: uint64, gas = 10000000'u64): ReportPolicyConfig =
  ## Keep gas limits per report, with independent pool/account byte ceilings.
  ReportPolicyConfig(pools: AuthorizationConfig(cores: CoreCount(cores), maxHashes: ElementLimit(cores*8),
    maxBytes: ByteLimit(100000)), accountBytes: ByteLimit(ServiceMetadataBytes),
        reportGas: ReportGasLimit(gas))


proc limits*(): StateStoreLimits =
  ## Bound sparse authored/projection maps used by tests; these are not a full-chain parent-state claim.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(1000), perValue: ByteLimit(100000),
    totalValueBytes: ByteLimit(1000000), nodes: TrieNodeLimit(100000)),
    writes: ElementLimit(1000), writeValueBytes: ByteLimit(1000000))


proc records*(owner: GuaranteesRead): seq[Guarantee] =
  ## Preserve each owned report when recovering a completely decoded extrinsic.
  result = newSeq[Guarantee](owner.count)
  for i in 0..<result.len:
    result[i] = guaranteeAt(owner.owner, i).value # Child retains its original bytes.


proc reportBytes*(owner: OwnedReport): seq[byte] =
  ## Copy canonical bytes while the original report owner remains alive.
  result = newSeq[byte](ownedReportInfo(owner).value.consumed)
  assert encodeOwnedReport(owner, result).error == OwnershipError.None


proc reportFor*(base: OwnedReport, core: int, gases: openArray[uint64], service = 42'u32,
    failed = false): OwnedReport =
  ## Alter only copied report metadata, then re-encode against the unchanged original payload pool.
  let raw = reportBytes(base)
  var report = decodeReportBorrowed(raw, 341).value
  report.core = CoreIndex(core)
  report.header.erasureShards = ErasureShards(6)
  report.authGas = Gas(high(uint64)) # Authorization gas is not accumulation gas.
  let first = report.digests[0]
  report.digestCount = gases.len
  for i in 0..<gases.len:
    report.digests[i] = first # Keep output/blob spans attached to raw for encoding.
    report.digests[i].service = ServiceIndex(service+uint32(i))
    report.digests[i].accumulateGas = Gas(gases[i])
    report.digests[i].refine.gasUsed = Gas(high(uint64)) # Refinement accounting is a separate gas domain.
    if failed:
      report.digests[i].output = failedWork(WorkKind.OutOfGas) # Failed work still carries accumulation gas policy.
  var output = newSeq[byte](raw.len+10000)
  let encoded = encodeReportBorrowed(report, raw, 2, output)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(output.toOpenArray(0, encoded.written-1), 2).value


proc certify*(reports: openArray[OwnedReport], slot = 12'u32, offenders: openArray[OffenderKey] = []): VerifiedGuaranteeCredentials =
  ## Sign authored reports with deterministic test keys and real assignments/transcripts, excluding supplied offenders.
  let config = credentialConfig(2)
  var keys = newSeq[EdSeed](6)
  var values = newSeq[StateValidator](6)
  for i in 0..<6:
    var seed = default(array[32, byte])
    seed[0] = byte(i+11)
    keys[i] = importSeed(seed).value
    values[i].ed25519 = StateEdKey(array[32, byte](publicKey(keys[i]).value)) # Test-only identities.
  let bytes = validatorEntry(ValidatorChapter.Active, values, config.assignments.roster).value.value
  let roster = decodeStateValidators(bytes, config.assignments.roster).value.value
  let plan = planGuarantors(roster, roster, default(StateEntropy), StateTime(slot), offenders,
      config.assignments).value
  var records: seq[Guarantee] = @[]
  # Each report retains independent core identity and complete owned bytes.
  for report in reports:
    var record = Guarantee(report: report, slot: GuaranteeSlot(slot), credentialCount: 2,
      credentials: default(array[3, GuaranteeCredential]))
    let message = array[45, byte](guaranteeMessage(reportBytes(report)).value)
    var found = 0
    for i in 0..<6:
      let assigned = plan.guarantorAt(record.slot, GuarantorIndex(i)).value
      let eligible = array[32, byte](assigned.validator.ed25519) == array[32, byte](values[i].ed25519)
      if uint64(assigned.core) == uint64(ownedReportInfo(report).value.core) and eligible and
          found < 2:
        record.credentials[found] = GuaranteeCredential(validator: GuarantorIndex(i),
          signature: GuaranteeSignature(array[64, byte](sign(keys[i],
              message).value))) # Ascending signer ordinals.
        inc found
    assert found == 2
    records.add(record)
  verifyGuaranteeCredentials(records, roster, roster, default(StateEntropy), StateTime(slot),
      offenders, config).value


proc entriesFor*(reports: openArray[OwnedReport], minimum = 10'u64): seq[StateEntry] =
  ## Construct exact parent pool and independently keyed service metadata for authored reports.
  var rows = newSeq[AuthorizerRow](2)
  # Each report retains independent core identity and complete owned bytes.
  for report in reports:
    let info = ownedReportInfo(report).value
    rows[int(uint64(info.core))] = @[info.authorizer] # Core-specific membership, not global membership.
  result = @[authorizationEntry(AuthorizationKind.Pools, rows, policy(2).pools).value]
  let report = reports[0]
  for i in 0..<ownedReportInfo(report).value.digestCount:
    let digest = ownedReportDigest(report, i).value
    let metadata = ServiceMetadata(codeHash: digest.codeHash, minimumAccumulationGas: Gas(minimum),
      minimumTransferGas: Gas(high(uint64)))
    result.add(serviceMetadataEntry(digest.service, metadata, ByteLimit(
        ServiceMetadataBytes)).value) # Transfer gas is deliberately unrelated.

