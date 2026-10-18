# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original signed package-relation projections and authored complete parent-pipeline/ownership boundaries.
import std/[assertions, envvars, strutils, syncio]
import ../../../src/state/[report_packages, report_anchors, report_policy, guarantee_credentials, store]
import ../../../src/codec/[bounded, guarantees, assurances, state_safrole, disputes, header,
  state_layout, state_trie, state_history, state_availability, state_workqueues,
  report_owned, owned, work_report, composite]
import ../../support/[arc_evidence, report_context]

## Refuse hashing after preparing valid inputs to prove the state-backed stage has no crypto/write side effects.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## Fixed eight-block history with explicit per-profile dictionaries and bounded serialized storage.
proc anchors(cores: uint64): ReportAnchorConfig =
  ReportAnchorConfig(history: HistoryConfig(cores: CoreCount(cores), blocks: ElementLimit(8),
    perBlock: ElementLimit(cores), totalPackages: ElementLimit(cores*8), peaks: ElementLimit(64),
    maxBytes: ByteLimit(1000000)), lookupAge: LookupAge(14400))

## Match upstream relation errors; lookup-key absence fails the same pair-subset check as a wrong root.
proc expected(text: string): ReportPackageError =
  case text
  of "ok": ReportPackageError.None # Complete applicable projection accepted.
  of "duplicate_package": ReportPackageError.DuplicatePackage # Incoming or prior occurrence.
  of "dependency_missing": ReportPackageError.MissingDependency # Prerequisite has no recent/current source.
  of "segment_root_lookup_invalid": ReportPackageError.InvalidSegmentRoot # Missing key or wrong associated root.
  else:
    assert false, text # No unrelated error can satisfy a selected case.
    ReportPackageError.Uninitialized

## Run relation checks on original published credential/history/known-set inputs, not fabricated queue chapters.
proc official(): OwnedReport {.raises.} =
  result = default(OwnedReport)
  var pools: seq[seq[byte]] = @[]
  var total = 0
  var accepted = 0
  var structural = 0
  # Every source case runs, including the two oversized dependency unions rejected by the codec.
  for row in readFile(getEnv("RAGNAROK_REPORT_PACKAGES")).splitLines:
    if row.len == 0: continue # Ignore the final transport newline only.
    let f = row.splitWhitespace
    if f[0] == "pool":
      pools.add(unhex(f[1])) # Immutable roster transport reuse does not alter any protocol field.
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
    # Preserve every original offender key and its order.
    for i in 0..<offenders.len:
      var key = default(array[32, byte])
      for j in 0..<32: key[j] = raw[i*32+j] # Exact source octets.
      offenders[i] = OffenderKey(key)
    let decoded = decodeGuarantees(unhex(f[9]), GuaranteeConfig(cores: CoreCount(cores),
      validators: ValidatorCount(cores*3), maxBytes: config.maxBytes))
    if f[3] == "too_many_dependencies":
      assert decoded.error == GuaranteeError.LimitExceeded, f[
          1] # Existing combined eight-dependency codec boundary.
      inc structural
      continue
    assert decoded.error == GuaranteeError.None, f[1]
    let credentials = verifyGuaranteeCredentials(records(decoded.value), active, previous, entropy,
      StateTime(parseInt(f[4])), offenders, config)
    assert credentials.error == GuaranteeCredentialError.None, f[1] & " " & $credentials.error
    var entries = @[StateEntry(key: chapterKey(StateChapter(1)), value: unhex(f[10]))]
    if f[11] != "-":
      # An absent metadata list must not create default service accounts.
      for account in f[11].split(','):
        let parts = account.split(':')
        entries.add(StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(parseInt(
            parts[0]))),
          value: unhex(parts[1]))) # Exact service identity and source fields.
    let parent = newStateStore(entries, limits()).value.snapshot.value
    let checked = checkReportPolicy(credentials.value, parent, policy(cores))
    assert checked.error == ReportPolicyError.None, f[1]
    let recent = checkRecentReportAnchors(checked.value, unhex(f[12]), StateTime(parseInt(f[4])),
        anchors(cores))
    assert recent.error == ReportAnchorError.None, f[1]
    let knownBytes = unhex(f[13])
    var known = newSeq[PackageHash](knownBytes.len div 32)
    # Transport known_packages exactly as a union, without inventing which chapter or slot held each key.
    for i in 0..<known.len:
      for j in 0..<32: known[i].bytes[j] = knownBytes[
          i*32+j] # Keep nominal package identities separate from roots.
    let reason = inspectReportPackages(credentials.value, recent.value.anchorHistory.value, known,
        ElementLimit(100000))
    assert reason == expected(f[3]), f[1] & " " & $reason
    if reason == ReportPackageError.None:
      inc accepted
      result = credentials.value.verifiedGuaranteeAt(
          0).value.report # Retains original full report after fixture scope.
  assert total == 32 and structural == 2 and accepted == 20

## Encode authored package identities/dependencies while keeping payload spans attached to the original pool.
proc reportForContext(base: OwnedReport, core: int, key: byte,
    prerequisites: openArray[PackageHash], lookups: openArray[SegmentLookup]): OwnedReport =
  let changed = reportFor(base, core, [10'u64])
  let original = reportBytes(changed)
  var value = decodeReportBorrowed(original, 2).value
  value.header.packageHash = PackageHash(bytes: default(array[32, byte]))
  value.header.packageHash.bytes[0] = key
  value.prerequisiteCount = prerequisites.len
  value.lookupCount = lookups.len
  # Authored arrays remain in supplied canonical order; production encoding checks their bounds/order.
  for i in 0..<prerequisites.len: value.prerequisites[i] = prerequisites[i]
  for i in 0..<lookups.len: value.lookup[i] = lookups[i] # Key and root stay paired.
  var wire = newSeq[byte](original.len+1024)
  let encoded = encodeReportBorrowed(value, original, 2, wire)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(wire.toOpenArray(0, encoded.written-1), 2).value

## Deterministic nominal key used only for authored package identities.
func key(value: byte): PackageHash =
  result = PackageHash(bytes: default(array[32, byte]))
  result.bytes[0] = value

## Small explicit state profile keeps epoch rings and aggregate index budgets independently bounded.
proc config(): ReportPackageConfig =
  ReportPackageConfig(availability: AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(2),
    validators: ValidatorCount(6), maxBytes: ByteLimit(100000)), maxPresent: ElementLimit(2),
        maxBytes: ByteLimit(200000)),
    queues: WorkQueueConfig(epochSlots: EpochSlots(12), cores: CoreCount(2), perSlot: ElementLimit(8),
      totalItems: ElementLimit(32), perDependencies: ElementLimit(8),
          totalDependencies: ElementLimit(256),
      reportBytes: ByteLimit(100000), maxBytes: ByteLimit(1000000)), indexItems: ElementLimit(1024))

## Reuse report anchor metadata as one corrected history tuple, with explicit authored package dictionary pairs.
proc historyBytes(report: OwnedReport, packages: seq[ReportedPackage]): seq[byte] =
  let fields = ownedReportInfo(report).value.header
  let record = HistoryBlock(header: HistoryHeaderHash(fields.anchor.bytes), state: HistoryStateRoot(
      fields.stateRoot.bytes),
    superPeak: HistorySuperPeak(fields.accumulationRoot.bytes), slot: HistorySlot(uint32(
        fields.anchorSlot)), packages: packages)
  historyStateEntry(HistoryState(blocks: @[record], peaks: @[]), anchors(2).history).value.value

## Build explicit parent chapters; mode selects an authored prior-pipeline duplicate or a deliberately different ready dependency.
proc entriesForContext(reports: openArray[OwnedReport], mode = 0): seq[StateEntry] =
  result = entriesFor(reports)
  let cfg = config()
  var assignments = newSeq[AvailabilityAssignment](2)
  var ready = newSeq[ReadyRow](12)
  var accumulated = newSeq[AccumulatedRow](12)
  case mode
  of 1:
    assignments[0] = presentAssignment(certify([reports[0]]).verifiedGuaranteeAt(0).value,
        AssignmentSlot(1)) # Prior, even if later expired/freed.
  of 2:
    ready[11] = @[ReadyItem(report: reports[0], dependencies: @[])] # Last slot, not just first row.
  of 3:
    accumulated[11] = @[ownedReportInfo(reports[0]).value.header.packageHash] # Every accumulated slot contributes.
  of 4:
    let different = reportForContext(reports[0], 0, 99, [], [])
    ready[3] = @[ReadyItem(report: different, dependencies: @[ownedReportInfo(reports[
        0]).value.header.packageHash])] # Dependency alone is not a queued report identity.
  else:
    discard # Explicit empty parent pipeline, not missing state.
  result.add(availabilityStateEntry(assignments, cfg.availability).value)
  result.add(readyStateEntry(ready, cfg.queues).value)
  result.add(accumulatedStateEntry(accumulated, cfg.queues).value)

## Bind the exact supplied complete-map projection through production credentials, policy and recent validation.
proc recentFor(reports: openArray[OwnedReport], entries: seq[StateEntry], history: seq[
    byte]): RecentAnchoredReports =
  let credentials = certify(reports)
  let parent = newStateStore(entries, limits()).value.snapshot.value
  let checked = checkReportPolicy(credentials, parent, policy(2)).value
  checkRecentReportAnchors(checked, history, StateTime(2000), anchors(2)).value

## Fresh parent decodes and index construction must release on complete success and later dependency refusal.
proc releaseCycle(recent: RecentAnchoredReports, expected: ReportPackageError) =
  assert checkReportPackages(recent, config()).error == expected # No certificate or transient index escapes.

## Exercise all exclusion sources, current/history-only dependencies, cycles, roots, malformed parents and retention.
proc boundaries(base: OwnedReport) =
  let first = reportForContext(base, 0, 10, [], [])
  let second = reportForContext(base, 1, 20, [], [])
  let history = historyBytes(first, @[])
  let entries = entriesForContext([first, second])
  let recent = recentFor([first, second], entries, history)
  let completed = checkReportPackages(recent, config())
  assert completed.error == ReportPackageError.None
  # Every prior pipeline source excludes the package, including a report waiting in the last ring row.
  for mode in 1..3:
    let context = recentFor([first], entriesForContext([first], mode), history)
    assert checkReportPackages(context, config()).error == ReportPackageError.DuplicatePackage
  let dependencyOnly = recentFor([first], entriesForContext([first], 4), history)
  assert checkReportPackages(dependencyOnly, config()).error == ReportPackageError.None
  let duplicate = reportForContext(base, 1, 10, [], [])
  let duplicateContext = recentFor([first, duplicate], entries, history)
  assert checkReportPackages(duplicateContext, config()).error ==
      ReportPackageError.DuplicatePackage
  let missing = reportForContext(base, 1, 20, [key(77)], [])
  let laterFailure = recentFor([first, missing], entries, history)
  assert checkReportPackages(laterFailure, config()).error == ReportPackageError.MissingDependency
  let cycleA = reportForContext(base, 0, 10, [key(20)], [])
  let cycleB = reportForContext(base, 1, 20, [key(10)], [])
  let cycle = recentFor([cycleA, cycleB], entries, history)
  assert checkReportPackages(cycle, config()).error ==
      ReportPackageError.None # No unauthorized DAG/topological restriction.
  let self = reportForContext(base, 0, 10, [key(10)], [])
  assert checkReportPackages(recentFor([self], entries, history), config()).error ==
      ReportPackageError.None
  let root = ownedReportInfo(first).value.header.segmentRoot
  let lookup = SegmentLookup(packageHash: key(10), segmentRoot: root)
  let consumer = reportForContext(base, 1, 20, [], [lookup])
  assert checkReportPackages(recentFor([first, consumer], entries, history), config()).error ==
      ReportPackageError.None
  let past = historyBytes(first, @[ReportedPackage(package: key(77), segment: root)])
  let needsPast = reportForContext(base, 0, 10, [key(77)], [SegmentLookup(packageHash: key(77),
      segmentRoot: root)])
  let pastContext = recentFor([needsPast], entries, past)
  assert checkReportPackages(pastContext, config()).error == ReportPackageError.None
  var wrongRoot = root
  wrongRoot.bytes[0] = wrongRoot.bytes[0] xor 1
  let wrong = reportForContext(base, 0, 10, [], [SegmentLookup(packageHash: key(77),
      segmentRoot: wrongRoot)])
  assert checkReportPackages(recentFor([wrong], entries, past), config()).error ==
      ReportPackageError.InvalidSegmentRoot
  let fromPipeline = reportForContext(base, 0, 10, [key(77)], [])
  var pipelineEntries = entries
  let cfg = config()
  var rows = newSeq[AccumulatedRow](12)
  rows[0] = @[key(77)]
  pipelineEntries[pipelineEntries.len-1] = accumulatedStateEntry(rows, cfg.queues).value
  let pipelineContext = recentFor([fromPipeline], pipelineEntries, history)
  assert checkReportPackages(pipelineContext, cfg).error == ReportPackageError.MissingDependency
  assert checkReportPackages(default(RecentAnchoredReports), cfg).error ==
      ReportPackageError.InvalidRecent
  assert default(PackageCheckedReports).packageRecent.error == ReportPackageError.Uninitialized
  # Missing, present-empty, truncated and suffixed chapters never become empty valid pipeline data.
  for chapter in 0..<3:
    let index = entries.len-3+chapter
    var absent = entries
    absent.delete(index)
    assert checkReportPackages(recentFor([first], absent, history), cfg).error ==
        ReportPackageError.MissingState
    var suffixed = entries[index].value
    suffixed.add(0)
    for malformed in [newSeq[byte](0), @[1'u8], suffixed]:
      var changed = entries
      changed[index].value = malformed
      assert checkReportPackages(recentFor([first], changed, history), cfg).error ==
          ReportPackageError.InvalidState, "malformed chapter " & $chapter
  var tight = cfg
  tight.indexItems = ElementLimit(1)
  assert checkReportPackages(recent, tight).error == ReportPackageError.LimitExceeded
  tight.indexItems = ElementLimit(2)
  assert checkReportPackages(recent, tight).error == ReportPackageError.None
  tight = cfg
  tight.availability.guarantee.cores = CoreCount(3)
  assert checkReportPackages(recent, tight).error == ReportPackageError.InvalidConfig
  tight = cfg
  tight.queues.maxBytes = ByteLimit(1)
  assert checkReportPackages(recent, tight).error == ReportPackageError.LimitExceeded
  tight = cfg
  tight.availability.maxBytes = ByteLimit(1)
  assert checkReportPackages(recent, tight).error == ReportPackageError.LimitExceeded
  let standalone = checkReportPackages(recentFor([first], entries, history), cfg).value
  assert standalone.packageRecent.value.recentPolicy.value.policyCredentials.value.verifiedGuaranteeCount.value == 1
  let originalParent = recent.recentPolicy.value.policyParent.value
  let emptyPolicy = checkReportPolicy(certify([]), originalParent, policy(2)).value
  let emptyRecent = checkRecentReportAnchors(emptyPolicy, history, StateTime(2000), anchors(2)).value
  assert checkReportPackages(emptyRecent, cfg).error == ReportPackageError.None
  let credentials = recent.recentPolicy.value.policyCredentials.value
  let noCredentials = default(VerifiedGuaranteeCredentials)
  let contextHistory = recent.anchorHistory.value
  assert inspectReportPackages(noCredentials, contextHistory, [], cfg.indexItems) ==
      ReportPackageError.InvalidCredentials
  assert inspectReportPackages(credentials, default(HistorySnapshot), [], cfg.indexItems) ==
      ReportPackageError.InvalidHistory
  assert inspectReportPackages(credentials, recent.anchorHistory.value, [], ElementLimit(high(
      uint64))) == ReportPackageError.LimitExceeded
  let certificate = completed.value.packageRecent.value
  failHash(1)
  assert checkReportPackages(certificate, cfg).error ==
      ReportPackageError.None # No hashing/state writes occur here.
  failHash(0)
  var detached = certificate.recentPolicy.value.policyParent.value.lookup(chapterKey(StateChapter(
      15))).value.bytes
  detached[0] = 255
  assert checkReportPackages(certificate, cfg).error == ReportPackageError.None
  releaseCycle(recent, ReportPackageError.None)
  releaseCycle(laterFailure, ReportPackageError.MissingDependency)
  let before = getOccupiedMem()
  for i in 0..<1000:
    if i mod 2 == 0:
      releaseCycle(recent, ReportPackageError.None) # Complete owner release.
    else:
      releaseCycle(laterFailure, ReportPackageError.MissingDependency) # First report was valid before later failure.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("report_packages", 1000, before, after)

## Missing input or failed assertions must fail the supported native runner.
proc main() {.raises.} =
  boundaries(official())
  echo "PASS report packages: thirty-two published projections, pipeline exclusions and dependency/root checks"
try:
  main() # All protocol assertions run in Nim.
except:
  quit(2) # Fixture transport failure cannot become a skipped successful suite.
