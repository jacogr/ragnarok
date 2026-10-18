## Original signed recent-anchor projections plus real full-header ancestry and lifecycle boundaries.
import std/[assertions, envvars, strutils, syncio]
import ../../../src/state/[report_anchors, report_policy, guarantee_credentials, store]
import ../../../src/codec/[bounded, guarantees, assurances, state_safrole, disputes, header,
  state_layout, state_trie, state_history, report_owned, owned, work_report, composite]
import ../../../src/crypto/primitives
import ../../support/[arc_evidence, report_context]

## Observe deterministic backend refusal without replacing any production hash calculation.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Permit a complete first ancestor hash before refusing the next one.
proc failAfter(count: cint) {.importc: "ro_blake_after", cdecl.}

## Same eight-block history domain in both published profiles, independently from lookup timeslot age.
proc anchorConfig(cores: uint64): ReportAnchorConfig =
  ReportAnchorConfig(history: HistoryConfig(cores: CoreCount(cores), blocks: ElementLimit(8),
    perBlock: ElementLimit(cores), totalPackages: ElementLimit(cores*8), peaks: ElementLimit(64),
    maxBytes: ByteLimit(1000000)), lookupAge: LookupAge(14400))

## Native fixture assertions require real credential and preceding policy success before testing context.
proc official(): OwnedReport {.raises.} =
  result = default(OwnedReport)
  var pools: seq[seq[byte]] = @[]
  var total = 0
  var accepted = 0
  # No published case may be silently dropped after an earlier successful projection.
  for row in readFile(getEnv("RAGNAROK_REPORT_ANCHORS")).splitLines:
    if row.len == 0: continue # Ignore only the trailing transport newline.
    let f = row.splitWhitespace
    if f[0] == "pool":
      pools.add(unhex(f[1])) # Pool identical immutable roster bytes only.
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
    # Copy offender identities exactly, preserving source order.
    for i in 0..<offenders.len:
      var key = default(array[32, byte])
      for j in 0..<32:
        key[j] = raw[i*32+j] # The planner owns canonicality, not fixture repair.
      offenders[i] = OffenderKey(key)
    let decoded = decodeGuarantees(unhex(f[9]), GuaranteeConfig(cores: CoreCount(cores),
      validators: ValidatorCount(cores*3), maxBytes: config.maxBytes))
    assert decoded.error == GuaranteeError.None, f[1]
    let credentials = verifyGuaranteeCredentials(records(decoded.value), active, previous, entropy,
      StateTime(parseInt(f[4])), offenders, config)
    assert credentials.error == GuaranteeCredentialError.None, f[1]
    var entries = @[StateEntry(key: chapterKey(StateChapter(1)), value: unhex(f[10]))]
    if f[11] != "-":
      for account in f[11].split(','):
        let parts = account.split(':')
        entries.add(StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(parseInt(
            parts[0]))),
          value: unhex(parts[1]))) # Keep exact account identity with its metadata.
    let parent = newStateStore(entries, limits()).value.snapshot.value
    let checked = checkReportPolicy(credentials.value, parent, policy(cores))
    assert checked.error == ReportPolicyError.None, f[1]
    let outcome = checkRecentReportAnchors(checked.value, unhex(f[12]), StateTime(parseInt(f[4])),
        anchorConfig(cores))
    if f[3] == "ok":
      assert outcome.error == ReportAnchorError.None, f[1]
      inc accepted
      result = credentials.value.verifiedGuaranteeAt(0).value.report # Survives every local fixture owner.
    else:
      assert f[3] in ["anchor_not_recent", "bad_anchor_slot", "bad_state_root", "bad_beefy_mmr_root"]
      assert outcome.error == ReportAnchorError.InvalidRecentAnchor, f[1] # One complete tuple is mandatory.
  assert total == 14 and accepted == 6

## Build exact owned sealed headers; the seal participates in the actual BLAKE2b header identity.
proc makeHeader(slot: uint32, parent, prior: array[32, byte], sealByte = 0'u8): OwnedHeader =
  var source = default(Header)
  source.unsigned.slot = HeaderSlot(slot)
  source.unsigned.parent = HeaderParent(parent)
  source.unsigned.priorState = PriorStateRoot(prior)
  var seal = default(array[96, byte])
  seal[0] = sealByte
  source.seal = HeaderSeal(seal)
  var wire = newSeq[byte](10000)
  let encoded = encodeHeader(source, fullHeaderConfig(ByteLimit(10000)), wire)
  assert encoded.error == HeaderError.None
  decodeHeader(wire.toOpenArray(0, encoded.value-1), fullHeaderConfig(ByteLimit(10000))).value.owner

## Hash canonical full sealed headers using the same public primitive as production.
proc headerHash(owner: OwnedHeader): array[32, byte] =
  var wire = newSeq[byte](headerInfo(owner).value.consumed)
  assert encodeOwnedHeader(owner, wire).error == HeaderError.None
  array[32, byte](blake2b256(wire).value)

## Re-sign only authored contexts; original published fixture credentials never pass through this helper.
proc withContext(base: OwnedReport, fields: ReportHeader): OwnedReport =
  let original = reportBytes(base)
  var source = decodeReportBorrowed(original, 341).value
  source.header = fields
  var wire = newSeq[byte](original.len+16)
  let encoded = encodeReportBorrowed(source, original, 2, wire)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(wire.toOpenArray(0, encoded.written-1), 2).value

## Create the preceding policy certificate through real signatures and service/pool validation.
proc checked(reports: openArray[OwnedReport]): PolicyCheckedReports =
  let credentials = certify(reports)
  let parent = newStateStore(entriesFor(reports), limits()).value.snapshot.value
  checkReportPolicy(credentials, parent, policy(2)).value

## Exact C(3) value containing the report's whole recent tuple, independent from lookup ancestry.
proc historyBytes(fields: ReportHeader): seq[byte] =
  let record = HistoryBlock(header: HistoryHeaderHash(fields.anchor.bytes),
    state: HistoryStateRoot(fields.stateRoot.bytes), superPeak: HistorySuperPeak(
        fields.accumulationRoot.bytes),
    slot: HistorySlot(uint32(fields.anchorSlot)), packages: @[])
  historyStateEntry(HistoryState(blocks: @[record], peaks: @[]), anchorConfig(
      2).history).value.value

## Retained-header resource ceilings are independent of report and history limits.
proc ancestors(): AncestorConfig =
  AncestorConfig(header: fullHeaderConfig(ByteLimit(10000)), headers: ElementLimit(8),
      maxBytes: ByteLimit(80000))

## Success and later-header hash refusal release all temporary recaptures and private owner chains.
proc releaseCycle(recent: RecentAnchoredReports, parent, oldest: OwnedHeader, refuse: bool) =
  if refuse:
    failAfter(1) # First header was fully captured before the next provider call refuses.
  let outcome = checkReportLookupAnchors(recent, parent, [oldest], ancestors())
  assert outcome.error == (if refuse: ReportAnchorError.BackendFailure else: ReportAnchorError.None)
  failHash(0) # Faults cannot escape this sequential observer-linked test.

## Check age arithmetic, full-seal ancestry, child-root direction, resource refusal and retained ownership.
proc boundaries(base: OwnedReport) =
  let zero = default(array[32, byte])
  var posterior = zero
  posterior[0] = 91
  let oldest = makeHeader(10, zero, zero)
  let parent = makeHeader(12, headerHash(oldest), posterior)
  var fields = ownedReportInfo(reportFor(base, 0, [10'u64])).value.header
  fields.anchor = BlockHash(bytes: headerHash(parent))
  fields.anchorSlot = AnchorSlot(12)
  fields.stateRoot = work_report.StateRoot(bytes: posterior)
  fields.lookupAnchor = BlockHash(bytes: headerHash(oldest))
  fields.lookupSlot = LookupSlot(10)
  fields.lookupStateRoot = LookupStateRoot(bytes: posterior)
  let report = withContext(reportFor(base, 0, [10'u64]), fields)
  let policy = checked([report])
  var history = historyBytes(fields)
  let config = anchorConfig(2)
  let recent = checkRecentReportAnchors(policy, history, StateTime(14), config).value
  let completed = checkReportLookupAnchors(recent, parent, [oldest], ancestors())
  assert completed.error == ReportAnchorError.None
  assert checkReportLookupAnchors(recent, parent, [], ancestors()).error ==
      ReportAnchorError.MissingLookupAnchor
  let resealed = makeHeader(10, zero, zero, 1)
  assert checkReportLookupAnchors(recent, parent, [resealed], ancestors()).error ==
      ReportAnchorError.BrokenAncestry
  assert checkReportLookupAnchors(recent, parent, [parent], ancestors()).error ==
      ReportAnchorError.BrokenAncestry
  assert checkReportLookupAnchors(recent, oldest, [parent], ancestors()).error ==
      ReportAnchorError.BrokenAncestry
  assert checkReportLookupAnchors(recent, default(OwnedHeader), [oldest], ancestors()).error ==
      ReportAnchorError.InvalidHeader
  let newest = makeHeader(13, headerHash(parent), posterior)
  assert checkReportLookupAnchors(recent, newest, [parent, oldest], ancestors()).error ==
      ReportAnchorError.None
  assert checkReportLookupAnchors(recent, newest, [oldest], ancestors()).error ==
      ReportAnchorError.BrokenAncestry
  failHash(1)
  assert checkReportLookupAnchors(recent, parent, [default(OwnedHeader)], ancestors()).error ==
      ReportAnchorError.InvalidHeader
  failHash(0) # All-owner preflight rejects before the first hash can fail.
  let wrongParent = makeHeader(12, headerHash(oldest), zero)
  assert checkReportLookupAnchors(recent, wrongParent, [oldest], ancestors()).error ==
      ReportAnchorError.WrongLookupState
  assert checkReportLookupAnchors(recent, makeHeader(14, headerHash(oldest), posterior), [oldest],
      ancestors()).error == ReportAnchorError.InvalidSlot
  var tight = ancestors()
  tight.headers = ElementLimit(1)
  assert checkReportLookupAnchors(recent, parent, [oldest], tight).error ==
      ReportAnchorError.LimitExceeded
  tight = ancestors()
  tight.maxBytes = ByteLimit(uint64(headerInfo(parent).value.consumed+headerInfo(
      oldest).value.consumed)-1)
  assert checkReportLookupAnchors(recent, parent, [oldest], tight).error ==
      ReportAnchorError.LimitExceeded
  tight.maxBytes = ByteLimit(uint64(tight.maxBytes)+1)
  assert checkReportLookupAnchors(recent, parent, [oldest], tight).error == ReportAnchorError.None
  tight = ancestors()
  tight.header.maxBytes = ByteLimit(1)
  assert checkReportLookupAnchors(recent, parent, [oldest], tight).error ==
      ReportAnchorError.LimitExceeded
  var age = config
  age.lookupAge = LookupAge(4)
  assert checkRecentReportAnchors(policy, history, StateTime(14), age).error ==
      ReportAnchorError.None
  age.lookupAge = LookupAge(3)
  assert checkRecentReportAnchors(policy, history, StateTime(14), age).error ==
      ReportAnchorError.LookupTooOld
  assert checkRecentReportAnchors(policy, history, StateTime(0), age).error ==
      ReportAnchorError.None # No unsigned genesis underflow; ancestor proof still required.
  age.lookupAge = LookupAge(high(uint64))
  assert checkRecentReportAnchors(policy, history, StateTime(high(uint32)), age).error ==
      ReportAnchorError.None
  age.lookupAge = LookupAge(14400)
  assert checkRecentReportAnchors(policy, history, StateTime(high(uint32)), age).error ==
      ReportAnchorError.LookupTooOld
  assert checkRecentReportAnchors(default(PolicyCheckedReports), history, StateTime(14),
      config).error == ReportAnchorError.InvalidPolicy
  let noRecent = default(RecentAnchoredReports)
  assert checkReportLookupAnchors(noRecent, parent, [oldest], ancestors()).error ==
      ReportAnchorError.InvalidRecent
  assert default(RecentAnchoredReports).recentPolicy.error == ReportAnchorError.Uninitialized
  assert default(RecentAnchoredReports).anchorHistory.error == ReportAnchorError.Uninitialized
  assert default(AnchoredReports).anchoredRecent.error == ReportAnchorError.Uninitialized
  var resource = config
  resource.history.maxBytes = ByteLimit(1)
  assert checkRecentReportAnchors(policy, history, StateTime(14), resource).error ==
      ReportAnchorError.LimitExceeded
  for malformed in [@[0'u8], @[0'u8, 0, 99]]:
    assert checkRecentReportAnchors(policy, malformed, StateTime(14), config).error ==
        ReportAnchorError.InvalidHistory # Truncation and suffix are refused.
  let genesis = checkRecentReportAnchors(policy, history, StateTime(0), config).value
  assert checkReportLookupAnchors(genesis, parent, [oldest], ancestors()).error ==
      ReportAnchorError.InvalidSlot
  var wrongFields = fields
  wrongFields.lookupSlot = LookupSlot(11)
  let wrong = checkRecentReportAnchors(checked([withContext(report, wrongFields)]), history,
      StateTime(14), config).value
  assert checkReportLookupAnchors(wrong, parent, [oldest], ancestors()).error ==
      ReportAnchorError.MissingLookupAnchor
  wrongFields = fields
  wrongFields.lookupSlot = LookupSlot(15)
  let future = checkRecentReportAnchors(checked([withContext(report, wrongFields)]), history,
      StateTime(14), config).value
  assert checkReportLookupAnchors(future, parent, [oldest], ancestors()).error ==
      ReportAnchorError.MissingLookupAnchor
  let emptyPolicy = checkReportPolicy(certify([]), policy.policyParent.value, report_context.policy(2)).value
  let empty = checkRecentReportAnchors(emptyPolicy, [0'u8, 0], StateTime(14), config).value
  assert checkReportLookupAnchors(empty, parent, [], ancestors()).error == ReportAnchorError.None
  assert checkRecentReportAnchors(policy, [0'u8, 0], StateTime(14), config).error ==
      ReportAnchorError.InvalidRecentAnchor
  let second = reportFor(report, 1, [10'u64])
  let batch = checkRecentReportAnchors(checked([report, second]), history, StateTime(14), config).value
  assert checkReportLookupAnchors(batch, parent, [oldest], ancestors()).error ==
      ReportAnchorError.None
  history[0] = 0
  assert historyInfo(completed.value.anchoredRecent.value.anchorHistory.value).value.blocks == 1
  assert completed.value.anchoredRecent.value.recentPolicy.value.policyCredentials.value.verifiedGuaranteeCount.value == 1
  releaseCycle(recent, parent, oldest, false)
  let before = getOccupiedMem()
  for i in 0..<1000:
    releaseCycle(recent, parent, oldest, i mod 2 == 1) # Alternate complete capture and later hash refusal.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("report_anchors", 1000, before, after)

## Missing fixture input and any assertion failure must fail the supported native runner.
proc main() {.raises.} =
  boundaries(official())
  echo "PASS report anchors: fourteen published projections, recent tuples and linked full-header proofs"
try:
  main() # Protocol verdicts remain native assertions.
except:
  quit(2) # Fallible transport cannot become a skipped successful suite.
