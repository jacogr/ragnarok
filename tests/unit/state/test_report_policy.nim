## Published signed report policy projections and authored gas, metadata, snapshot and release boundaries.
import std/[assertions, envvars, strutils, parseutils, syncio]
import ../../../src/state/[report_policy, guarantee_credentials, guarantors, store]
import ../../../src/codec/[guarantees, assurances, bounded, state_safrole, disputes,
  report_owned, owned, work_report, work_digest, composite, header, state_accounts,
  state_authorization, state_layout, state_trie]
import ../../../src/crypto/[primitives, guarantee]
import ../../support/arc_evidence

## Refuse hashing after input preparation to prove policy has no crypto/state-write side effects.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## Decode trusted fixture transport exactly; a dash denotes an empty sequence only.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty transport is distinct from a fabricated state value.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    assert parseHex(text[i*2..i*2+1], result[i]) == 2 # Require complete octets.

## Configure both published populations without conflating roster size and active core count.
proc credentialConfig(cores: uint64): GuaranteeCredentialConfig =
  GuaranteeCredentialConfig(assignments: GuarantorConfig(roster: ValidatorStateConfig(
    cores: CoreCount(cores), validators: ElementLimit(cores*3), maxBytes: ByteLimit(400000)),
    epochSlots: EpochSlots(if cores == 341: 600 else: 12),
    rotationSlots: GuarantorRotationSlots(if cores == 341: 10 else: 4), offenders: ElementLimit(
        cores*3)),
    maxBytes: ByteLimit(10000000), reporters: ElementLimit(cores*3))

## Keep gas limits per report, with independent pool/account byte ceilings.
proc policy(cores: uint64, gas = 10000000'u64): ReportPolicyConfig =
  ReportPolicyConfig(pools: AuthorizationConfig(cores: CoreCount(cores), maxHashes: ElementLimit(cores*8),
    maxBytes: ByteLimit(100000)), accountBytes: ByteLimit(89), reportGas: ReportGasLimit(gas))

## Bound sparse authored/projection maps used by tests; these are not a full-chain parent-state claim.
proc limits(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(1000), perValue: ByteLimit(100000),
    totalValueBytes: ByteLimit(1000000), nodes: TrieNodeLimit(100000)),
    writes: ElementLimit(1000), writeValueBytes: ByteLimit(1000000))

## Preserve each owned report when recovering a completely decoded extrinsic.
proc records(owner: GuaranteesRead): seq[Guarantee] =
  result = newSeq[Guarantee](owner.count)
  for i in 0..<result.len:
    result[i] = guaranteeAt(owner.owner, i).value # Child retains its original bytes.

## Match exact published policy errors, never treating an earlier credential failure as success.
proc expected(text: string): ReportPolicyError =
  case text
  of "ok": ReportPolicyError.None # Published acceptance exercises the complete policy stage.
  of "core_unauthorized": ReportPolicyError.Unauthorized # Parent core-specific membership.
  of "bad_service_id": ReportPolicyError.UnknownService # Missing account is not zero metadata.
  of "bad_code_hash": ReportPolicyError.WrongCodeHash # Service-specific code commitment.
  of "service_item_gas_too_low": ReportPolicyError.InsufficientGas # Per-digest minimum.
  of "work_report_gas_too_high": ReportPolicyError.ReportGasExceeded # Per-report aggregate ceiling.
  else:
    assert false, text # No unreviewed scenario can silently enter this fixture family.
    ReportPolicyError.Uninitialized

## Verify unchanged signed tiny/full projections against their source policy verdicts.
proc official(): OwnedReport {.raises.} =
  result = default(OwnedReport)
  var pools: seq[seq[byte]] = @[]
  var total = 0
  var accepted = 0
  # Visit every source case; none may be skipped after an earlier success.
  for row in readFile(getEnv("RAGNAROK_REPORT_POLICY")).splitLines:
    if row.len == 0: continue # Only the transport's final empty line is ignored.
    let f = row.splitWhitespace
    if f[0] == "pool":
      pools.add(unhex(f[1])) # Repeated rosters share immutable transport bytes.
      continue
    inc total
    let cores = uint64(parseInt(f[2]))
    let config = credentialConfig(cores)
    let active = decodeStateValidators(pools[parseInt(f[5])], config.assignments.roster).value.value
    let previous = decodeStateValidators(pools[parseInt(f[6])],
        config.assignments.roster).value.value
    let entropy = decodeStateEntropy(unhex(f[7])).value.value
    let raw = unhex(f[8])
    var offenders = newSeq[OffenderKey](raw.len div 32)
    # Preserve the supplied offender identities before credential verification.
    for i in 0..<offenders.len:
      var key = default(array[32, byte])
      for j in 0..<32:
        key[j] = raw[i*32+j] # Preserve source key identities and ordering.
      offenders[i] = OffenderKey(key)
    let wire = GuaranteeConfig(cores: CoreCount(cores), validators: ValidatorCount(cores*3),
        maxBytes: config.maxBytes)
    let decoded = decodeGuarantees(unhex(f[9]), wire)
    assert decoded.error == GuaranteeError.None, f[1]
    let credentials = verifyGuaranteeCredentials(records(decoded.value), active, previous, entropy,
      StateTime(parseInt(f[4])), offenders, config)
    assert credentials.error == GuaranteeCredentialError.None, f[1] & " " & $credentials.error
    var entries = @[StateEntry(key: chapterKey(StateChapter(1)), value: unhex(f[10]))]
    if f[11] != "-": # Absent transport entries remain absent metadata keys.
      for account in f[11].split(','):
        let parts = account.split(':')
        entries.add(StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(parseInt(
            parts[0]))),
          value: unhex(parts[1]))) # Exact service IDs and original fixed metadata.
    let state = newStateStore(entries, limits()).value
    let parent = state.snapshot.value
    let outcome = checkReportPolicy(credentials.value, parent, policy(cores))
    assert outcome.error == expected(f[3]), f[1] & " " & $outcome.error
    if outcome.error == ReportPolicyError.None:
      inc accepted
      result = outcome.value.policyCredentials.value.verifiedGuaranteeAt(
          0).value.report # Retained after fixture scope.
    assert array[32, byte](parent.commitment.root) == array[32, byte](
        state.snapshot.value.commitment.root)
  assert total == 20 and accepted == 8

## Copy canonical bytes while the original report owner remains alive.
proc reportBytes(owner: OwnedReport): seq[byte] =
  result = newSeq[byte](ownedReportInfo(owner).value.consumed)
  assert encodeOwnedReport(owner, result).error == OwnershipError.None

## Alter only copied report metadata, then re-encode against the unchanged original payload pool.
proc reportFor(base: OwnedReport, core: int, gases: openArray[uint64], service = 42'u32,
    failed = false): OwnedReport =
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

## Sign authored reports with deterministic public test keys and the real assignment/transcript machinery.
proc certify(reports: openArray[OwnedReport]): VerifiedGuaranteeCredentials =
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
  let plan = planGuarantors(roster, roster, default(StateEntropy), StateTime(12), [],
      config.assignments).value
  var records: seq[Guarantee] = @[]
  # Each report retains independent core identity and complete owned bytes.
  for report in reports:
    var record = Guarantee(report: report, slot: GuaranteeSlot(12), credentialCount: 2,
      credentials: default(array[3, GuaranteeCredential]))
    let message = array[45, byte](guaranteeMessage(reportBytes(report)).value)
    var found = 0
    for i in 0..<6:
      if uint64(plan.guarantorAt(record.slot, GuarantorIndex(i)).value.core) == uint64(
          ownedReportInfo(report).value.core) and found < 2:
        record.credentials[found] = GuaranteeCredential(validator: GuarantorIndex(i),
          signature: GuaranteeSignature(array[64, byte](sign(keys[i],
              message).value))) # Ascending signer ordinals.
        inc found
    assert found == 2
    records.add(record)
  verifyGuaranteeCredentials(records, roster, roster, default(StateEntropy), StateTime(12), [], config).value

## Construct exact parent pool and independently keyed service metadata for authored reports.
proc entriesFor(reports: openArray[OwnedReport], minimum = 10'u64): seq[StateEntry] =
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
        89)).value) # Transfer gas is deliberately unrelated.

## A scoped success or later-digest refusal must release every certificate and snapshot handle.
proc releaseCycle(credentials: VerifiedGuaranteeCredentials, parent: StateStoreSnapshot,
    config: ReportPolicyConfig) =
  discard checkReportPolicy(credentials, parent, config) # No result escapes this cycle.

## Exercise exact limits, overflow, malformed parent values, retained identity and nonmutating failures.
proc boundaries(base: OwnedReport) =
  let one = reportFor(base, 0, [10'u64, 20])
  let two = reportFor(base, 1, [10'u64, 20])
  let credentials = certify([one, two])
  var entries = entriesFor([one, two])
  var state = newStateStore(entries, limits()).value
  let parent = state.snapshot.value
  let original = array[32, byte](parent.commitment.root)
  let completed = checkReportPolicy(credentials, parent, policy(2, 30))
  assert completed.error == ReportPolicyError.None # Two exact-cap reports, not a 60-gas batch ceiling.
  assert checkReportPolicy(credentials, parent, policy(2, 29)).error ==
      ReportPolicyError.ReportGasExceeded
  assert checkReportPolicy(credentials, parent, policy(2, 9)).error ==
      ReportPolicyError.ReportGasExceeded
  let huge = certify([reportFor(base, 0, [high(uint64), 1])])
  assert checkReportPolicy(huge, parent, policy(2, high(uint64))).error ==
      ReportPolicyError.ReportGasExceeded
  let low = certify([reportFor(base, 0, [9'u64])])
  assert checkReportPolicy(low, parent, policy(2)).error == ReportPolicyError.InsufficientGas
  let failed = certify([reportFor(base, 0, [9'u64], failed = true)])
  assert checkReportPolicy(failed, parent, policy(2)).error == ReportPolicyError.InsufficientGas
  var laterEntries = entries
  laterEntries[2].value[1] = laterEntries[2].value[1] xor 1
  let laterParent = newStateStore(laterEntries, limits()).value.snapshot.value
  assert checkReportPolicy(credentials, laterParent, policy(2)).error ==
      ReportPolicyError.WrongCodeHash
  let zeroReport = reportFor(base, 0, [0'u64])
  let zero = certify([zeroReport])
  let zeroState = newStateStore(entriesFor([zeroReport], 0), limits()).value.snapshot.value
  assert checkReportPolicy(zero, zeroState, policy(2, 0)).error == ReportPolicyError.None
  assert checkReportPolicy(default(VerifiedGuaranteeCredentials), parent, policy(2)).error ==
      ReportPolicyError.InvalidCredentials
  assert checkReportPolicy(credentials, default(StateStoreSnapshot), policy(2)).error ==
      ReportPolicyError.InvalidState
  assert default(PolicyCheckedReports).policyCredentials.error == ReportPolicyError.Uninitialized
  assert default(PolicyCheckedReports).policyParent.error == ReportPolicyError.Uninitialized
  let empty = certify([])
  let absent = newStateStore([], limits()).value.snapshot.value
  assert checkReportPolicy(empty, absent, policy(2)).error == ReportPolicyError.MissingState
  assert checkReportPolicy(empty, parent, policy(2)).error == ReportPolicyError.None
  var tight = policy(2)
  tight.accountBytes = ByteLimit(88)
  assert checkReportPolicy(credentials, parent, tight).error == ReportPolicyError.InvalidConfig
  tight = policy(2)
  tight.pools.maxBytes = ByteLimit(1)
  assert checkReportPolicy(credentials, parent, tight).error == ReportPolicyError.LimitExceeded
  tight = policy(2)
  tight.pools.maxHashes = ElementLimit(1)
  assert checkReportPolicy(credentials, parent, tight).error == ReportPolicyError.LimitExceeded
  for malformed in [@[1'u8], @[0'u8, 0, 9], @[9'u8]]:
    let bad = newStateStore([StateEntry(key: chapterKey(StateChapter(1)), value: malformed)],
        limits()).value.snapshot.value
    assert checkReportPolicy(credentials, bad, policy(2)).error ==
        ReportPolicyError.InvalidState # Truncated, suffix and excessive row count.
  let noAccounts = newStateStore(entries.toOpenArray(0, 0), limits()).value.snapshot.value
  assert checkReportPolicy(credentials, noAccounts, policy(2)).error ==
      ReportPolicyError.UnknownService
  # Refuse each malformed account representation without altering the retained parent.
  for mode in 0..<5:
    var changed = entries
    if mode == 0:
      changed[1].value[1] = changed[1].value[1] xor 1 # Wrong code belongs to an existing service.
    elif mode == 1:
      changed[1].value[0] = 1 # Unsupported metadata version.
    elif mode == 2:
      changed[1].value = @[] # Present-empty is not an absent service or zero metadata.
    elif mode == 3:
      changed[1].value.setLen(88) # Fixed metadata truncation.
    else:
      changed[1].value.add(0) # Exact state values cannot contain a suffix.
    let bad = newStateStore(changed, limits()).value.snapshot.value
    assert checkReportPolicy(credentials, bad, policy(2)).error == (if mode ==
        0: ReportPolicyError.WrongCodeHash else: ReportPolicyError.InvalidState)
  var wrongRows = newSeq[AuthorizerRow](2)
  wrongRows[1] = @[ownedReportInfo(one).value.authorizer]
  let wrongPool = authorizationEntry(AuthorizationKind.Pools, wrongRows, policy(2).pools).value
  var wrongEntries = entries
  wrongEntries[0] = wrongPool
  let wrongState = newStateStore(wrongEntries, limits()).value.snapshot.value
  assert checkReportPolicy(credentials, wrongState, policy(2)).error ==
      ReportPolicyError.Unauthorized
  failHash(1)
  assert checkReportPolicy(credentials, parent, policy(2)).error ==
      ReportPolicyError.None # No hashing or mutation in read-only policy.
  failHash(0)
  let writes = [StateWrite(key: chapterKey(StateChapter(1)), kind: StateWriteKind.Put, value: @[
      0'u8, 0])]
  assert state.apply(writes).error == StateStoreError.None
  entries[0].value = @[0'u8, 0]
  var detached = completed.value.policyParent.value.lookup(chapterKey(StateChapter(1))).value.bytes
  detached[0] = 0
  assert array[32, byte](completed.value.policyParent.value.commitment.root) == original
  assert checkReportPolicy(completed.value.policyCredentials.value,
      completed.value.policyParent.value, policy(2)).error == ReportPolicyError.None
  assert checkReportPolicy(credentials, state.snapshot.value, policy(2)).error ==
      ReportPolicyError.Unauthorized
  releaseCycle(credentials, parent, policy(2))
  let before = getOccupiedMem()
  for i in 0..<1000:
    releaseCycle(credentials, parent, policy(2, if i mod 2 ==
        0: 30'u64 else: 29)) # Include refusal after a valid first digest.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("report_policy", 1000, before, after)

## Missing fixtures and any failed assertion must fail the native runner.
proc main() {.raises.} =
  boundaries(official())
  echo "PASS report policy: twenty published projections, gas boundaries and retained parent state"
try:
  main() # Native assertions own every application verdict.
except:
  quit(2) # Fixture I/O failures cannot become empty successful runs.
